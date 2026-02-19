defmodule JidoConversation.Runtime.EffectWorker do
  @moduledoc """
  Executes one effect directive asynchronously with retry, timeout, and cancellation.
  """

  use GenServer, restart: :temporary

  require Logger

  alias JidoConversation.Ingest

  @type state :: %{
          effect_id: String.t(),
          conversation_id: String.t(),
          class: :llm | :tool | :timer,
          kind: String.t() | atom(),
          input: map(),
          cause_id: String.t() | nil,
          manager: pid(),
          attempt: non_neg_integer(),
          max_attempts: pos_integer(),
          backoff_ms: pos_integer(),
          timeout_ms: pos_integer(),
          simulate: map(),
          task: Task.t() | nil,
          timeout_ref: reference() | nil
        }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @spec cancel(pid(), String.t(), String.t() | nil) :: :ok
  def cancel(pid, reason, cause_id \\ nil) when is_pid(pid) and is_binary(reason) do
    GenServer.cast(pid, {:cancel, reason, cause_id})
  end

  @impl true
  def init(opts) do
    state = %{
      effect_id: Keyword.fetch!(opts, :effect_id),
      conversation_id: Keyword.fetch!(opts, :conversation_id),
      class: Keyword.fetch!(opts, :class),
      kind: Keyword.get(opts, :kind, "default"),
      input: normalize_map(Keyword.get(opts, :input, %{})),
      cause_id: Keyword.get(opts, :cause_id),
      manager: Keyword.fetch!(opts, :manager),
      attempt: 0,
      max_attempts: policy_value(opts, :max_attempts),
      backoff_ms: policy_value(opts, :backoff_ms),
      timeout_ms: policy_value(opts, :timeout_ms),
      simulate: normalize_map(Keyword.get(opts, :simulate, %{})),
      task: nil,
      timeout_ref: nil
    }

    send(self(), :run_attempt)
    {:ok, state}
  end

  @impl true
  def handle_cast({:cancel, reason, cancel_cause_id}, state) do
    state = clear_in_flight(state)

    emit_lifecycle(
      state,
      "canceled",
      %{attempt: state.attempt, reason: reason},
      cancel_cause_id || state.cause_id
    )

    notify_finished(state)
    {:stop, :normal, state}
  end

  @impl true
  def handle_info(:run_attempt, state) do
    attempt = state.attempt + 1
    state = %{state | attempt: attempt}

    if attempt == 1 do
      emit_lifecycle(state, "started", %{attempt: attempt})
    else
      emit_lifecycle(state, "progress", %{attempt: attempt, status: "retry_attempt_started"})
    end

    task = Task.async(fn -> execute_attempt(state, attempt) end)

    timeout_ref =
      Process.send_after(self(), {:attempt_timeout, task.ref, attempt}, state.timeout_ms)

    {:noreply, %{state | task: task, timeout_ref: timeout_ref}}
  end

  @impl true
  def handle_info({task_ref, {:ok, result}}, %{task: %Task{ref: task_ref}} = state) do
    state = clear_in_flight(state)

    emit_lifecycle(state, "progress", %{attempt: state.attempt, status: "result_received"})
    emit_lifecycle(state, "completed", %{attempt: state.attempt, result: result})

    notify_finished(state)
    {:stop, :normal, state}
  end

  @impl true
  def handle_info({task_ref, {:error, reason}}, %{task: %Task{ref: task_ref}} = state) do
    case retry_or_fail(state, reason) do
      {:retry, state} -> {:noreply, state}
      {:stop, state} -> {:stop, :normal, state}
    end
  end

  @impl true
  def handle_info(
        {:DOWN, task_ref, :process, _pid, reason},
        %{task: %Task{ref: task_ref}} = state
      ) do
    case retry_or_fail(state, {:task_exit, reason}) do
      {:retry, state} -> {:noreply, state}
      {:stop, state} -> {:stop, :normal, state}
    end
  end

  @impl true
  def handle_info({:attempt_timeout, task_ref, attempt}, %{task: %Task{ref: task_ref}} = state)
      when attempt == state.attempt do
    case retry_or_fail(state, :timeout) do
      {:retry, state} -> {:noreply, state}
      {:stop, state} -> {:stop, :normal, state}
    end
  end

  @impl true
  def handle_info(_message, state) do
    {:noreply, state}
  end

  defp retry_or_fail(state, reason) do
    state = clear_in_flight(state)

    if state.attempt < state.max_attempts do
      backoff = backoff_for_attempt(state.backoff_ms, state.attempt)

      emit_lifecycle(state, "progress", %{
        attempt: state.attempt,
        status: "retrying",
        backoff_ms: backoff,
        reason: inspect(reason)
      })

      Process.send_after(self(), :run_attempt, backoff)
      {:retry, state}
    else
      emit_lifecycle(state, "failed", %{attempt: state.attempt, reason: inspect(reason)})
      notify_finished(state)
      {:stop, state}
    end
  end

  defp notify_finished(state) do
    send(state.manager, {:effect_finished, state.effect_id})
  end

  defp clear_in_flight(state) do
    _ =
      if is_reference(state.timeout_ref) do
        Process.cancel_timer(state.timeout_ref)
      else
        :ok
      end

    if is_struct(state.task, Task) do
      _ = Task.shutdown(state.task, :brutal_kill)
      Process.demonitor(state.task.ref, [:flush])
    end

    %{state | task: nil, timeout_ref: nil}
  end

  defp execute_attempt(state, attempt) do
    latency = latency_for_attempt(state, attempt)

    if latency > 0 do
      Process.sleep(latency)
    end

    force_fail_attempts = int_value(state.simulate, :force_fail_attempts, 0)

    if attempt <= force_fail_attempts do
      {:error, :forced_failure}
    else
      {:ok, %{kind: state.kind, class: Atom.to_string(state.class), attempt: attempt}}
    end
  end

  defp emit_lifecycle(state, lifecycle, extra_data, cause_id \\ nil) do
    attrs = %{
      type: "#{effect_type_prefix(state.class)}.#{lifecycle}",
      source: "/runtime/effects/#{state.class}",
      subject: state.conversation_id,
      data:
        %{
          effect_id: state.effect_id,
          lifecycle: lifecycle,
          effect_class: Atom.to_string(state.class),
          kind: to_string(state.kind)
        }
        |> Map.merge(extra_data),
      extensions: %{"contract_major" => 1}
    }

    case ingest_with_cause(attrs, cause_id || state.cause_id) do
      {:ok, _result} ->
        :ok

      {:error, reason} ->
        Logger.warning("failed to ingest effect lifecycle #{attrs.type}: #{inspect(reason)}")
        :ok
    end
  end

  defp effect_type_prefix(:llm), do: "conv.effect.llm.generation"
  defp effect_type_prefix(:tool), do: "conv.effect.tool.execution"
  defp effect_type_prefix(:timer), do: "conv.effect.timer.wait"

  defp backoff_for_attempt(backoff_ms, attempt) do
    multiplier = :math.pow(2, max(attempt - 1, 0))
    trunc(backoff_ms * multiplier)
  end

  defp latency_for_attempt(state, attempt) do
    latency_overrides = normalize_map(get_field(state.simulate, :latency_ms_by_attempt))

    case get_field(latency_overrides, attempt) do
      nil ->
        int_value(state.simulate, :latency_ms, 5)

      value when is_integer(value) and value >= 0 ->
        value

      value when is_binary(value) ->
        case Integer.parse(value) do
          {int, ""} when int >= 0 -> int
          _ -> 5
        end

      _ ->
        5
    end
  end

  defp policy_value(opts, key) do
    policy = Keyword.fetch!(opts, :policy)
    Keyword.fetch!(policy, key)
  end

  defp int_value(map, key, default) do
    case get_field(map, key) do
      value when is_integer(value) and value >= 0 ->
        value

      value when is_binary(value) ->
        case Integer.parse(value) do
          {int, ""} when int >= 0 -> int
          _ -> default
        end

      _ ->
        default
    end
  end

  defp get_field(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, to_string(key))
  end

  defp get_field(_map, _key), do: nil

  defp normalize_map(value) when is_map(value), do: value
  defp normalize_map(_value), do: %{}

  defp ingest_with_cause(attrs, nil), do: Ingest.ingest(attrs)

  defp ingest_with_cause(attrs, cause_id) when is_binary(cause_id) do
    case Ingest.ingest(attrs, cause_id: cause_id) do
      {:ok, result} ->
        {:ok, result}

      {:error, {:journal_record_failed, :cause_not_found}} ->
        Logger.warning(
          "effect lifecycle cause_id missing from journal, ingesting without cause_id: #{inspect(cause_id)}"
        )

        Ingest.ingest(attrs)

      {:error, {:invalid_cause_id, _reason}} ->
        Logger.warning(
          "effect lifecycle cause_id invalid, ingesting without cause_id: #{inspect(cause_id)}"
        )

        Ingest.ingest(attrs)

      other ->
        other
    end
  end
end
