defmodule JidoConversation.Runtime.EffectWorker do
  @moduledoc """
  Executes one effect directive asynchronously with retry, timeout, and cancellation.
  """

  use GenServer, restart: :temporary

  require Logger

  alias JidoConversation.Config
  alias JidoConversation.Ingest
  alias JidoConversation.LLM.Error, as: LLMError
  alias JidoConversation.LLM.Event, as: LLMEvent
  alias JidoConversation.LLM.Request, as: LLMRequest
  alias JidoConversation.LLM.Resolver, as: LLMResolver
  alias JidoConversation.LLM.Result, as: LLMResult

  @backend_option_string_keys %{
    "llm_client" => :llm_client,
    "llm_client_module" => :llm_client_module,
    "llm_client_context" => :llm_client_context,
    "jido_ai_module" => :jido_ai_module,
    "harness_module" => :harness_module,
    "harness_provider" => :harness_provider,
    "provider" => :provider,
    "session_id" => :session_id
  }

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
          worker_pid: pid(),
          llm_cancel_context: map() | nil,
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
      worker_pid: self(),
      llm_cancel_context: nil,
      task: nil,
      timeout_ref: nil
    }

    send(self(), :run_attempt)
    {:ok, state}
  end

  @impl true
  def handle_cast({:cancel, reason, cancel_cause_id}, state) do
    {state, backend_cancel_data} = maybe_cancel_backend(state)
    state = clear_in_flight(state)

    emit_lifecycle(
      state,
      "canceled",
      %{
        attempt: state.attempt,
        reason: reason
      }
      |> Map.merge(backend_cancel_data),
      cancel_cause_id || state.cause_id
    )

    notify_finished(state)
    {:stop, :normal, state}
  end

  @impl true
  def handle_info(:run_attempt, state) do
    attempt = state.attempt + 1
    state = %{state | attempt: attempt, llm_cancel_context: nil}

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
  def handle_info(
        {:llm_cancel_context, attempt, module, backend_opts, execution_ref},
        %{attempt: attempt, task: %Task{}} = state
      )
      when is_atom(module) and is_list(backend_opts) do
    next_context =
      merge_llm_cancel_context(
        state.llm_cancel_context,
        %{
          attempt: attempt,
          module: module,
          backend_opts: backend_opts,
          execution_ref: execution_ref
        }
      )

    {:noreply, %{state | llm_cancel_context: next_context}}
  end

  @impl true
  def handle_info({task_ref, {:ok, result}}, %{task: %Task{ref: task_ref}} = state) do
    state = clear_in_flight(state)

    if state.class != :llm do
      emit_lifecycle(state, "progress", %{attempt: state.attempt, status: "result_received"})
    end

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

    if state.attempt < state.max_attempts and retryable_reason?(reason) do
      backoff = backoff_for_attempt(state.backoff_ms, state.attempt)

      emit_lifecycle(state, "progress", %{
        attempt: state.attempt,
        status: "retrying",
        backoff_ms: backoff,
        reason: failure_reason(reason),
        retryable?: retryable_reason?(reason)
      })

      Process.send_after(self(), :run_attempt, backoff)
      {:retry, state}
    else
      emit_lifecycle(state, "failed", failure_payload(reason, state.attempt))
      notify_finished(state)
      {:stop, state}
    end
  end

  defp failure_payload(%LLMError{} = error, attempt) do
    %{
      attempt: attempt,
      reason: error.message,
      error_category: Atom.to_string(error.category),
      retryable?: error.retryable?,
      details: normalize_map(error.details)
    }
  end

  defp failure_payload(reason, attempt) do
    %{
      attempt: attempt,
      reason: failure_reason(reason),
      retryable?: retryable_reason?(reason)
    }
  end

  defp failure_reason(%LLMError{} = error), do: error.message
  defp failure_reason(reason), do: inspect(reason)

  defp retryable_reason?(%LLMError{} = error), do: error.retryable?
  defp retryable_reason?(_reason), do: true

  defp maybe_cancel_backend(%{class: :llm} = state) do
    case state.llm_cancel_context do
      %{module: module, backend_opts: backend_opts, execution_ref: execution_ref}
      when is_atom(module) and is_list(backend_opts) and not is_nil(execution_ref) ->
        cancel_data =
          case ensure_backend_function(module, :cancel, 2) do
            :ok ->
              normalize_cancel_result(
                invoke_backend(module, :cancel, [execution_ref, backend_opts])
              )

            {:error, %LLMError{} = error} ->
              cancel_error_data(error)
          end

        {state, cancel_data}

      _ ->
        {state, %{backend_cancel: "not_available"}}
    end
  end

  defp maybe_cancel_backend(state), do: {state, %{}}

  defp normalize_cancel_result({:ok, :ok}), do: %{backend_cancel: "ok"}
  defp normalize_cancel_result({:ok, {:ok, _value}}), do: %{backend_cancel: "ok"}

  defp normalize_cancel_result({:ok, {:error, %LLMError{} = error}}), do: cancel_error_data(error)

  defp normalize_cancel_result({:ok, {:error, reason}}) do
    %{
      backend_cancel: "failed",
      backend_cancel_reason: inspect(reason)
    }
  end

  defp normalize_cancel_result({:ok, other}) do
    %{
      backend_cancel: "failed",
      backend_cancel_reason: "invalid_response",
      backend_cancel_details: inspect(other)
    }
  end

  defp normalize_cancel_result({:error, %LLMError{} = error}), do: cancel_error_data(error)

  defp cancel_error_data(%LLMError{} = error) do
    %{
      backend_cancel: "failed",
      backend_cancel_reason: error.message,
      backend_cancel_category: Atom.to_string(error.category),
      backend_cancel_retryable?: error.retryable?
    }
  end

  defp merge_llm_cancel_context(nil, context), do: context

  defp merge_llm_cancel_context(existing, context) when is_map(existing) and is_map(context) do
    execution_ref = context.execution_ref || Map.get(existing, :execution_ref)
    Map.merge(existing, context) |> Map.put(:execution_ref, execution_ref)
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

    %{state | task: nil, timeout_ref: nil, llm_cancel_context: nil}
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
      execute_attempt_for_class(state, attempt)
    end
  end

  defp execute_attempt_for_class(%{class: :llm} = state, attempt) do
    with {:ok, execution} <- resolve_llm_execution(state),
         {:ok, request} <- build_llm_request(state, execution, attempt),
         {:ok, result, execution_ref} <- execute_llm_backend(state, execution, request, attempt) do
      {:ok, llm_result_payload(result, execution, execution_ref)}
    else
      {:error, %LLMError{} = error} ->
        {:error, error}
    end
  end

  defp execute_attempt_for_class(state, attempt) do
    {:ok, %{kind: state.kind, class: Atom.to_string(state.class), attempt: attempt}}
  end

  defp resolve_llm_execution(state) do
    effect_overrides = normalize_map(state.input)
    conversation_defaults = llm_conversation_defaults(state.input)

    case LLMResolver.resolve(effect_overrides, conversation_defaults, Config.llm()) do
      {:ok, resolved} ->
        {:ok, resolved}

      {:error, %LLMError{} = error} ->
        {:error, error}
    end
  end

  defp build_llm_request(state, execution, attempt) do
    input = normalize_map(state.input)

    request_attrs = %{
      request_id: "#{state.effect_id}:#{attempt}",
      conversation_id: state.conversation_id,
      backend: execution.backend,
      messages: llm_messages(input),
      model: first_non_nil([get_field(input, :model), execution.model]),
      provider: first_non_nil([get_field(input, :provider), execution.provider]),
      system_prompt:
        first_non_nil([get_field(input, :system_prompt), get_field(input, :instructions)]),
      stream?: execution.stream?,
      max_tokens: optional_positive_int(get_field(input, :max_tokens)),
      temperature: optional_number(get_field(input, :temperature)),
      timeout_ms:
        first_non_nil([
          execution.timeout_ms,
          optional_positive_int(get_field(input, :timeout_ms))
        ]),
      metadata: llm_request_metadata(state, attempt),
      options: llm_request_options(input)
    }

    case LLMRequest.new(request_attrs) do
      {:ok, request} ->
        {:ok, request}

      {:error, reason} ->
        {:error,
         LLMError.new!(
           category: :config,
           message: "invalid llm request payload",
           details: %{request: request_attrs, reason: reason}
         )}
    end
  end

  defp execute_llm_backend(state, execution, request, attempt) do
    backend_opts = backend_options(execution.options)
    module = execution.module
    _ = notify_llm_cancel_context(state, attempt, module, backend_opts, nil)

    if request.stream? do
      emit = fn
        %LLMEvent{} = event ->
          _ = maybe_capture_stream_execution_ref(state, attempt, module, backend_opts, event)
          emit_llm_stream_progress(state, attempt, event)

        _other ->
          :ok
      end

      with :ok <- ensure_backend_function(module, :stream, 3),
           {:ok, response} <- invoke_backend(module, :stream, [request, emit, backend_opts]) do
        capture_backend_response(state, attempt, module, backend_opts, response)
      end
    else
      with :ok <- ensure_backend_function(module, :start, 2),
           {:ok, response} <- invoke_backend(module, :start, [request, backend_opts]) do
        capture_backend_response(state, attempt, module, backend_opts, response)
      end
    end
  end

  defp capture_backend_response(state, attempt, module, backend_opts, response) do
    case normalize_backend_response(response) do
      {:ok, _result, execution_ref} = ok ->
        _ = notify_llm_cancel_context(state, attempt, module, backend_opts, execution_ref)
        ok

      other ->
        other
    end
  end

  defp ensure_backend_function(module, function, arity) when is_atom(module) do
    cond do
      not Code.ensure_loaded?(module) ->
        {:error,
         LLMError.new!(
           category: :config,
           message: "llm backend module is not available",
           details: %{module: module, function: function, arity: arity}
         )}

      not function_exported?(module, function, arity) ->
        {:error,
         LLMError.new!(
           category: :config,
           message: "llm backend module is missing required callback",
           details: %{module: module, function: function, arity: arity}
         )}

      true ->
        :ok
    end
  end

  defp invoke_backend(module, function, args) do
    {:ok, apply(module, function, args)}
  rescue
    error ->
      {:error, LLMError.from_reason(error, :unknown, message: Exception.message(error))}
  catch
    kind, reason ->
      {:error, LLMError.from_reason({kind, reason}, :unknown)}
  end

  defp normalize_backend_response({:ok, %LLMResult{status: :completed} = result}) do
    {:ok, result, nil}
  end

  defp normalize_backend_response({:ok, %LLMResult{status: :completed} = result, execution_ref}) do
    {:ok, result, execution_ref}
  end

  defp normalize_backend_response({:ok, %LLMResult{} = result}) do
    {:error, llm_non_completed_error(result)}
  end

  defp normalize_backend_response({:ok, %LLMResult{} = result, _execution_ref}) do
    {:error, llm_non_completed_error(result)}
  end

  defp normalize_backend_response({:error, %LLMError{} = error}), do: {:error, error}

  defp normalize_backend_response({:error, reason}) do
    {:error, LLMError.from_reason(reason, :provider, message: "llm backend execution failed")}
  end

  defp normalize_backend_response(other) do
    {:error,
     LLMError.new!(
       category: :provider,
       message: "llm backend returned an invalid response tuple",
       details: %{response: other}
     )}
  end

  defp llm_non_completed_error(%LLMResult{status: :failed} = result) do
    result.error ||
      LLMError.new!(
        category: :provider,
        message: "llm backend returned a failed result",
        details: %{result: Map.from_struct(result)}
      )
  end

  defp llm_non_completed_error(%LLMResult{status: :canceled} = result) do
    result.error ||
      LLMError.new!(
        category: :canceled,
        message: "llm backend returned a canceled result",
        details: %{result: Map.from_struct(result)}
      )
  end

  defp llm_non_completed_error(%LLMResult{} = result) do
    LLMError.new!(
      category: :unknown,
      message: "llm backend returned an unsupported result status",
      details: %{status: result.status}
    )
  end

  defp emit_llm_stream_progress(state, attempt, %LLMEvent{lifecycle: :delta} = event) do
    token_delta = normalize_binary(event.delta)

    if is_binary(token_delta) do
      emit_lifecycle(
        state,
        "progress",
        compact_map(%{
          attempt: attempt,
          status: "streaming",
          token_delta: token_delta,
          sequence: event.sequence,
          provider: normalize_identifier(event.provider),
          model: normalize_identifier(event.model),
          backend: normalize_identifier(event.backend)
        })
      )
    end

    :ok
  end

  defp emit_llm_stream_progress(state, attempt, %LLMEvent{lifecycle: :thinking} = event) do
    thinking_delta = normalize_binary(event.content)

    if is_binary(thinking_delta) do
      emit_lifecycle(
        state,
        "progress",
        compact_map(%{
          attempt: attempt,
          status: "thinking",
          thinking_delta: thinking_delta,
          sequence: event.sequence,
          provider: normalize_identifier(event.provider),
          model: normalize_identifier(event.model),
          backend: normalize_identifier(event.backend)
        })
      )
    end

    :ok
  end

  defp emit_llm_stream_progress(_state, _attempt, _event), do: :ok

  defp maybe_capture_stream_execution_ref(
         state,
         attempt,
         module,
         backend_opts,
         %LLMEvent{} = event
       ) do
    case execution_ref_from_event(event) do
      nil ->
        :ok

      execution_ref ->
        notify_llm_cancel_context(state, attempt, module, backend_opts, execution_ref)
    end
  end

  defp execution_ref_from_event(%LLMEvent{} = event) do
    metadata = normalize_map(event.metadata)
    explicit_ref = get_field(metadata, :execution_ref)

    if is_nil(explicit_ref) do
      session_id = normalize_binary(get_field(metadata, :session_id))

      provider =
        first_non_nil([
          normalize_identifier(event.provider),
          normalize_identifier(get_field(metadata, :provider))
        ])

      if is_binary(session_id) and is_binary(provider) do
        %{provider: provider, session_id: session_id}
      end
    else
      explicit_ref
    end
  end

  defp notify_llm_cancel_context(state, attempt, module, backend_opts, execution_ref) do
    send(
      state.worker_pid,
      {:llm_cancel_context, attempt, module, backend_opts, execution_ref}
    )

    :ok
  end

  defp llm_result_payload(%LLMResult{} = result, execution, execution_ref) do
    base =
      %{
        status: normalize_identifier(result.status),
        text: result.text,
        model:
          first_non_nil([
            normalize_identifier(result.model),
            normalize_identifier(execution.model)
          ]),
        provider:
          first_non_nil([
            normalize_identifier(result.provider),
            normalize_identifier(execution.provider)
          ]),
        finish_reason: normalize_identifier(result.finish_reason),
        usage: normalize_map(result.usage),
        metadata:
          result.metadata
          |> normalize_map()
          |> Map.put(:backend, normalize_identifier(execution.backend))
      }
      |> compact_map()

    if is_nil(execution_ref) do
      base
    else
      Map.put(base, :execution_ref, inspect(execution_ref))
    end
  end

  defp llm_messages(input) do
    input
    |> get_field(:messages)
    |> case do
      messages when is_list(messages) and messages != [] ->
        Enum.map(messages, &normalize_llm_message/1)

      _ ->
        [
          %{
            role: normalize_role(get_field(input, :role)),
            content: default_llm_content(input)
          }
        ]
    end
  end

  defp normalize_llm_message(message) when is_map(message) do
    %{
      role: normalize_role(get_field(message, :role)),
      content:
        first_non_nil([
          get_field(message, :content),
          get_field(message, :text),
          ""
        ])
    }
  end

  defp normalize_llm_message(_message), do: %{role: :user, content: ""}

  defp llm_request_metadata(state, attempt) do
    state.input
    |> get_field(:metadata)
    |> normalize_map()
    |> Map.put_new(:effect_id, state.effect_id)
    |> Map.put_new(:attempt, attempt)
    |> Map.put_new(:class, Atom.to_string(state.class))
  end

  defp llm_request_options(input) do
    input
    |> get_field(:request_options)
    |> normalize_map()
  end

  defp llm_conversation_defaults(input) do
    first_non_nil([
      get_field(input, :conversation_defaults),
      get_field(input, :conversation_llm_defaults),
      %{}
    ])
    |> normalize_map()
  end

  defp backend_options(options) when is_map(options) do
    options
    |> Enum.reduce([], fn
      {key, value}, acc when is_atom(key) ->
        [{key, value} | acc]

      {key, value}, acc when is_binary(key) ->
        atom_key =
          Map.get(@backend_option_string_keys, key) ||
            existing_atom_key(key)

        if is_atom(atom_key) do
          [{atom_key, value} | acc]
        else
          acc
        end

      _entry, acc ->
        acc
    end)
    |> Enum.reverse()
  end

  defp existing_atom_key(key) when is_binary(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> nil
  end

  defp default_llm_content(input) do
    first_non_nil([
      get_field(input, :content),
      get_field(input, :text),
      get_field(input, :prompt),
      ""
    ])
  end

  defp normalize_role(nil), do: :user
  defp normalize_role(role) when role in [:user, :assistant, :system, :tool], do: role

  defp normalize_role(role) when is_binary(role) do
    case String.downcase(String.trim(role)) do
      "assistant" -> :assistant
      "system" -> :system
      "tool" -> :tool
      _ -> :user
    end
  end

  defp normalize_role(_), do: :user

  defp optional_positive_int(value) when is_integer(value) and value > 0, do: value

  defp optional_positive_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} when int > 0 -> int
      _ -> nil
    end
  end

  defp optional_positive_int(_), do: nil

  defp optional_number(value) when is_number(value), do: value

  defp optional_number(value) when is_binary(value) do
    case Float.parse(value) do
      {float, ""} -> float
      _ -> nil
    end
  end

  defp optional_number(_), do: nil

  defp normalize_binary(value) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: nil, else: value
  end

  defp normalize_binary(_), do: nil

  defp normalize_identifier(nil), do: nil
  defp normalize_identifier(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_identifier(value) when is_binary(value), do: value
  defp normalize_identifier(value) when is_number(value), do: to_string(value)
  defp normalize_identifier(_), do: nil

  defp first_non_nil(values) when is_list(values) do
    Enum.find(values, &(not is_nil(&1)))
  end

  defp compact_map(map) when is_map(map) do
    Enum.reduce(map, %{}, fn
      {_key, nil}, acc -> acc
      {key, value}, acc -> Map.put(acc, key, value)
    end)
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
    case Map.fetch(map, key) do
      {:ok, value} ->
        value

      :error ->
        Map.get(map, to_string(key))
    end
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
