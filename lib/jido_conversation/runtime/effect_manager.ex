defmodule JidoConversation.Runtime.EffectManager do
  @moduledoc """
  Manages in-flight effect workers and cancellation for conversation runtime.

  Effect workers execute directives asynchronously and emit `conv.effect.*`
  lifecycle signals through ingestion.
  """

  use GenServer

  require Logger

  alias JidoConversation.Config
  alias JidoConversation.Ingest
  alias JidoConversation.Runtime.EffectWorker

  @type effect_class :: :llm | :tool | :timer

  @type effect_payload :: %{
          required(:effect_id) => String.t(),
          required(:conversation_id) => String.t(),
          required(:class) => effect_class(),
          optional(:kind) => String.t() | atom(),
          optional(:input) => map(),
          optional(:simulate) => map(),
          optional(:policy) => keyword() | map()
        }

  @type state :: %{
          effects: %{
            String.t() => %{
              pid: pid(),
              monitor_ref: reference(),
              class: effect_class(),
              conversation_id: String.t()
            }
          },
          monitors: %{reference() => String.t()},
          by_conversation: %{String.t() => MapSet.t(String.t())}
        }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec start_effect(effect_payload(), String.t() | nil) :: :ok
  def start_effect(effect_payload, cause_id \\ nil) when is_map(effect_payload) do
    GenServer.cast(__MODULE__, {:start_effect, effect_payload, cause_id})
  end

  @spec cancel_conversation(String.t(), String.t(), String.t() | nil) :: :ok
  def cancel_conversation(conversation_id, reason, cause_id \\ nil)
      when is_binary(conversation_id) and is_binary(reason) do
    GenServer.cast(__MODULE__, {:cancel_conversation, conversation_id, reason, cause_id})
  end

  @spec stats() :: map()
  def stats do
    GenServer.call(__MODULE__, :stats)
  end

  @impl true
  def init(_opts) do
    {:ok, %{effects: %{}, monitors: %{}, by_conversation: %{}}}
  end

  @impl true
  def handle_cast({:start_effect, payload, cause_id}, state) do
    state =
      case normalize_payload(payload) do
        {:ok, normalized} ->
          maybe_start_worker(state, normalized, cause_id)

        {:error, reason} ->
          Logger.warning("dropping invalid effect directive: #{inspect(reason)}")
          state
      end

    {:noreply, state}
  end

  @impl true
  def handle_cast({:cancel_conversation, conversation_id, reason, cause_id}, state) do
    state.by_conversation
    |> Map.get(conversation_id, MapSet.new())
    |> Enum.each(fn effect_id ->
      case Map.get(state.effects, effect_id) do
        %{pid: pid} when is_pid(pid) ->
          EffectWorker.cancel(pid, reason, cause_id)

        _ ->
          :ok
      end
    end)

    {:noreply, state}
  end

  @impl true
  def handle_call(:stats, _from, state) do
    by_conversation =
      Enum.into(state.by_conversation, %{}, fn {conversation_id, effect_ids} ->
        {conversation_id, Enum.sort(effect_ids)}
      end)

    stats = %{
      in_flight_count: map_size(state.effects),
      in_flight_effect_ids: state.effects |> Map.keys() |> Enum.sort(),
      by_conversation: by_conversation
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_info({:effect_finished, effect_id}, state) when is_binary(effect_id) do
    {:noreply, remove_effect(state, effect_id)}
  end

  @impl true
  def handle_info({:DOWN, monitor_ref, :process, _pid, _reason}, state) do
    case Map.get(state.monitors, monitor_ref) do
      nil ->
        {:noreply, state}

      effect_id ->
        {:noreply, remove_effect(state, effect_id)}
    end
  end

  defp maybe_start_worker(state, payload, cause_id) do
    if Map.has_key?(state.effects, payload.effect_id) do
      state
    else
      do_start_worker(state, payload, cause_id)
    end
  end

  defp do_start_worker(state, payload, cause_id) do
    policy = merge_policy(Config.effect_runtime_policy(payload.class), payload.policy)

    worker_opts = [
      effect_id: payload.effect_id,
      conversation_id: payload.conversation_id,
      class: payload.class,
      kind: payload.kind,
      input: payload.input,
      policy: policy,
      simulate: payload.simulate,
      cause_id: cause_id,
      manager: self()
    ]

    case DynamicSupervisor.start_child(
           JidoConversation.Runtime.EffectSupervisor,
           {EffectWorker, worker_opts}
         ) do
      {:ok, pid} ->
        monitor_ref = Process.monitor(pid)

        effect_info = %{
          pid: pid,
          monitor_ref: monitor_ref,
          class: payload.class,
          conversation_id: payload.conversation_id
        }

        %{
          state
          | effects: Map.put(state.effects, payload.effect_id, effect_info),
            monitors: Map.put(state.monitors, monitor_ref, payload.effect_id),
            by_conversation:
              Map.update(
                state.by_conversation,
                payload.conversation_id,
                MapSet.new([payload.effect_id]),
                &MapSet.put(&1, payload.effect_id)
              )
        }

      {:error, reason} ->
        Logger.warning("failed to start effect worker #{payload.effect_id}: #{inspect(reason)}")
        emit_start_failure(payload, cause_id, reason)
        state
    end
  end

  defp remove_effect(state, effect_id) do
    case Map.pop(state.effects, effect_id) do
      {nil, _effects} ->
        state

      {%{monitor_ref: monitor_ref, conversation_id: conversation_id}, effects} ->
        conversation_effects =
          state.by_conversation
          |> Map.get(conversation_id, MapSet.new())
          |> MapSet.delete(effect_id)

        by_conversation =
          if MapSet.size(conversation_effects) == 0 do
            Map.delete(state.by_conversation, conversation_id)
          else
            Map.put(state.by_conversation, conversation_id, conversation_effects)
          end

        %{
          state
          | effects: effects,
            monitors: Map.delete(state.monitors, monitor_ref),
            by_conversation: by_conversation
        }
    end
  end

  defp normalize_payload(payload) when is_map(payload) do
    effect_id = get_field(payload, :effect_id)
    conversation_id = get_field(payload, :conversation_id)
    class = get_field(payload, :class)

    cond do
      not non_empty_binary?(effect_id) ->
        {:error, {:invalid_effect_id, effect_id}}

      not non_empty_binary?(conversation_id) ->
        {:error, {:invalid_conversation_id, conversation_id}}

      class not in [:llm, :tool, :timer] ->
        {:error, {:invalid_class, class}}

      true ->
        {:ok,
         %{
           effect_id: effect_id,
           conversation_id: conversation_id,
           class: class,
           kind: get_field(payload, :kind) || "default",
           input: normalize_map(get_field(payload, :input)),
           simulate: normalize_map(get_field(payload, :simulate)),
           policy: get_field(payload, :policy) || []
         }}
    end
  end

  defp normalize_payload(other), do: {:error, {:invalid_payload, other}}

  defp emit_start_failure(payload, cause_id, reason) do
    attrs = %{
      type: "#{effect_type_prefix(payload.class)}.failed",
      source: "/runtime/effects/manager",
      subject: payload.conversation_id,
      data: %{
        effect_id: payload.effect_id,
        lifecycle: "failed",
        reason: inspect(reason),
        attempt: 0
      },
      extensions: %{"contract_major" => 1}
    }

    case ingest_with_cause(attrs, cause_id) do
      {:ok, _result} ->
        :ok

      {:error, ingest_reason} ->
        Logger.warning(
          "failed to ingest effect start failure lifecycle: #{inspect(ingest_reason)}"
        )

        :ok
    end
  end

  defp effect_type_prefix(:llm), do: "conv.effect.llm.generation"
  defp effect_type_prefix(:tool), do: "conv.effect.tool.execution"
  defp effect_type_prefix(:timer), do: "conv.effect.timer.wait"

  defp merge_policy(default_policy, override_policy) when is_list(override_policy) do
    Keyword.merge(default_policy, override_policy)
  end

  defp merge_policy(default_policy, override_policy) when is_map(override_policy) do
    Keyword.merge(default_policy, Map.to_list(override_policy))
  end

  defp merge_policy(default_policy, _override_policy), do: default_policy

  defp ingest_with_cause(attrs, nil), do: Ingest.ingest(attrs)

  defp ingest_with_cause(attrs, cause_id) when is_binary(cause_id) do
    case Ingest.ingest(attrs, cause_id: cause_id) do
      {:ok, result} ->
        {:ok, result}

      {:error, {:journal_record_failed, :cause_not_found}} ->
        Logger.warning(
          "effect failure cause_id missing from journal, ingesting without cause_id: #{inspect(cause_id)}"
        )

        Ingest.ingest(attrs)

      {:error, {:invalid_cause_id, _reason}} ->
        Logger.warning(
          "effect failure cause_id invalid, ingesting without cause_id: #{inspect(cause_id)}"
        )

        Ingest.ingest(attrs)

      other ->
        other
    end
  end

  defp get_field(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, to_string(key))
  end

  defp normalize_map(value) when is_map(value), do: value
  defp normalize_map(_value), do: %{}

  defp non_empty_binary?(value) when is_binary(value), do: String.trim(value) != ""
  defp non_empty_binary?(_value), do: false
end
