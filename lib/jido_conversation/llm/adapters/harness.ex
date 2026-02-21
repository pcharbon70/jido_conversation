defmodule JidoConversation.LLM.Adapters.Harness do
  @moduledoc """
  `JidoHarness` backend adapter for the unified LLM client contract.

  This adapter calls `Jido.Harness` dynamically so `jido_conversation` can
  compile without requiring `jido_harness` in all environments.
  """

  @behaviour JidoConversation.LLM.Backend

  alias JidoConversation.LLM.Error
  alias JidoConversation.LLM.Event
  alias JidoConversation.LLM.Request
  alias JidoConversation.LLM.Result

  @default_harness_module Jido.Harness

  @known_harness_providers %{
    "codex" => :codex,
    "amp" => :amp,
    "claude" => :claude,
    "gemini" => :gemini,
    "opencode" => :opencode
  }

  @mapped_string_options %{
    "cwd" => :cwd,
    "model" => :model,
    "max_turns" => :max_turns,
    "timeout_ms" => :timeout_ms,
    "system_prompt" => :system_prompt,
    "allowed_tools" => :allowed_tools,
    "attachments" => :attachments,
    "metadata" => :metadata,
    "transport" => :transport,
    "cli_path" => :cli_path,
    "amp_cli_path" => :amp_cli_path,
    "mode" => :mode,
    "dangerously_allow_all" => :dangerously_allow_all,
    "harness_provider" => :harness_provider,
    "provider" => :provider
  }

  @network_reasons [:econnrefused, :nxdomain, :closed, :enetdown, :ehostunreach]
  @timeout_reasons [:timeout, :connect_timeout, :checkout_timeout, :receive_timeout]

  @impl true
  def capabilities do
    %{
      streaming?: true,
      cancellation?: cancellation_supported?(),
      provider_selection?: false,
      model_selection?: false
    }
  end

  @impl true
  def start(%Request{} = request, opts) when is_list(opts) do
    with {:ok, invocation} <- invoke_harness(request, opts),
         {:ok, state} <- consume_stream(invocation.stream, request, nil, init_state(invocation)),
         {:ok, result} <- build_result(request, state) do
      {:ok, result}
    else
      {:error, %Error{} = error} ->
        {:error, error}

      {:error, reason} ->
        {:error, normalize_error(reason)}
    end
  end

  @impl true
  def stream(%Request{} = request, emit_event, opts)
      when is_function(emit_event, 1) and is_list(opts) do
    with {:ok, invocation} <- invoke_harness(request, opts),
         :ok <- emit_started_event(request, emit_event, invocation.provider),
         {:ok, state} <-
           consume_stream(invocation.stream, request, emit_event, init_state(invocation)),
         {:ok, result} <- build_result(request, state),
         :ok <- emit_terminal_event(request, emit_event, result, state) do
      {:ok, result}
    else
      {:error, %Error{} = error} ->
        _ = emit_failed_event(request, emit_event, error)
        {:error, error}

      {:error, reason} ->
        error = normalize_error(reason)
        _ = emit_failed_event(request, emit_event, error)
        {:error, error}
    end
  end

  @impl true
  def cancel(execution_ref, opts) when is_list(opts) do
    harness_module = harness_module(opts)

    with :ok <- ensure_function(harness_module, :cancel, 2),
         {:ok, provider} <- resolve_cancel_provider(execution_ref, opts),
         {:ok, session_id} <- resolve_cancel_session_id(execution_ref, opts),
         {:ok, response} <- invoke_plain(harness_module, :cancel, [provider, session_id]),
         :ok <- validate_cancel_response(response) do
      :ok
    else
      {:error, %Error{} = error} ->
        {:error, error}

      {:error, reason} ->
        {:error, normalize_error(reason)}
    end
  end

  defp cancellation_supported? do
    Code.ensure_loaded?(@default_harness_module) and
      function_exported?(@default_harness_module, :cancel, 2)
  end

  defp invoke_harness(%Request{} = request, opts) do
    harness_module = harness_module(opts)

    with {:ok, prompt} <- build_prompt(request),
         {:ok, run_opts} <- build_run_opts(request),
         {:ok, provider} <- resolve_harness_provider(run_opts, opts),
         {:ok, tuple} <- run_harness(harness_module, provider, prompt, run_opts),
         {:ok, stream} <- normalize_stream_result(tuple) do
      {:ok, %{provider: provider, stream: stream}}
    end
  end

  defp run_harness(harness_module, provider, prompt, run_opts) when is_atom(provider) do
    with :ok <- ensure_function(harness_module, :run, 3),
         {:ok, response} <- invoke_plain(harness_module, :run, [provider, prompt, run_opts]),
         :ok <- validate_harness_tuple(response) do
      {:ok, response}
    end
  end

  defp run_harness(harness_module, nil, prompt, run_opts) do
    with :ok <- ensure_function(harness_module, :run, 2),
         {:ok, response} <- invoke_plain(harness_module, :run, [prompt, run_opts]),
         :ok <- validate_harness_tuple(response) do
      {:ok, response}
    end
  end

  defp normalize_stream_result({:ok, stream}) do
    if Enumerable.impl_for(stream) != nil do
      {:ok, stream}
    else
      {:ok, [stream]}
    end
  end

  defp normalize_stream_result(other) do
    {:error,
     Error.new!(
       category: :provider,
       message: "harness backend returned an invalid stream payload",
       details: %{payload: other}
     )}
  end

  defp validate_harness_tuple({:ok, _stream}), do: :ok
  defp validate_harness_tuple({:error, _reason}), do: :ok

  defp validate_harness_tuple(other) do
    {:error,
     Error.new!(
       category: :provider,
       message: "harness backend returned an invalid tuple",
       details: %{response: other}
     )}
  end

  defp consume_stream(stream, request, emit_event, state) do
    Enum.reduce_while(stream, {:ok, state}, fn raw_event, {:ok, acc} ->
      case process_event(raw_event, request, emit_event, acc) do
        {:ok, next_state} ->
          {:cont, {:ok, next_state}}

        {:error, %Error{} = error, next_state} ->
          {:halt, {:error, error, next_state}}
      end
    end)
    |> normalize_consumption_result()
  rescue
    error ->
      {:error, normalize_error(error)}
  catch
    kind, reason ->
      {:error, normalize_error({kind, reason})}
  end

  defp normalize_consumption_result({:ok, state}), do: {:ok, state}
  defp normalize_consumption_result({:error, error, _state}), do: {:error, error}

  defp process_event(raw_event, request, emit_event, state) do
    event = normalize_harness_event(raw_event, state.provider)

    state =
      state
      |> update_state_from_event(event)
      |> apply_delta_chunks(event, request, emit_event)
      |> apply_thinking_chunks(event, request, emit_event)
      |> apply_usage(event)
      |> apply_finish_reason(event)
      |> apply_final_text(event)

    terminal_state(event, state)
  end

  defp update_state_from_event(state, event) do
    state
    |> Map.put(:provider, event.provider || state.provider)
    |> Map.put(:session_id, event.session_id || state.session_id)
    |> Map.update!(:event_count, &(&1 + 1))
  end

  defp apply_delta_chunks(state, event, request, emit_event) do
    event
    |> extract_delta_chunks()
    |> Enum.reduce(state, fn text, acc ->
      _ = emit_delta_event(request, emit_event, acc.provider, acc.session_id, text)
      Map.update!(acc, :text_chunks, &[text | &1])
    end)
  end

  defp apply_thinking_chunks(state, event, request, emit_event) do
    event
    |> extract_thinking_chunks()
    |> Enum.reduce(state, fn text, acc ->
      _ = emit_thinking_event(request, emit_event, acc.provider, acc.session_id, text)
      Map.update!(acc, :thinking_chunks, &[text | &1])
    end)
  end

  defp apply_usage(state, event) do
    case extract_usage(event) do
      %{} = usage when map_size(usage) > 0 -> Map.put(state, :usage, usage)
      _ -> state
    end
  end

  defp apply_finish_reason(state, event) do
    case extract_finish_reason(event) do
      nil -> state
      finish_reason -> Map.put(state, :finish_reason, finish_reason)
    end
  end

  defp apply_final_text(state, event) do
    case extract_final_text_candidate(event) do
      nil -> state
      text -> Map.put(state, :final_text, text)
    end
  end

  defp terminal_state(event, state) do
    cond do
      failed_event?(event) ->
        error = normalize_failed_event(event)
        {:error, error, %{state | status: :failed, error: error}}

      canceled_event?(event) ->
        {:ok, %{state | status: :canceled, finish_reason: state.finish_reason || :canceled}}

      completed_event?(event) ->
        {:ok, %{state | status: :completed}}

      true ->
        {:ok, state}
    end
  end

  defp emit_started_event(request, emit_event, provider) do
    emit_event_safe(
      emit_event,
      Event.new!(%{
        request_id: request.request_id,
        conversation_id: request.conversation_id,
        backend: request.backend,
        lifecycle: :started,
        provider: provider,
        metadata: %{
          stream?: request.stream?,
          timeout_ms: request.timeout_ms
        }
      })
    )
  end

  defp emit_delta_event(_request, nil, _provider, _session_id, _text), do: :ok

  defp emit_delta_event(request, emit_event, provider, session_id, text) do
    emit_event_safe(
      emit_event,
      Event.new!(%{
        request_id: request.request_id,
        conversation_id: request.conversation_id,
        backend: request.backend,
        lifecycle: :delta,
        provider: provider,
        delta: text,
        metadata: execution_metadata(provider, session_id)
      })
    )
  end

  defp emit_thinking_event(_request, nil, _provider, _session_id, _text), do: :ok

  defp emit_thinking_event(request, emit_event, provider, session_id, text) do
    emit_event_safe(
      emit_event,
      Event.new!(%{
        request_id: request.request_id,
        conversation_id: request.conversation_id,
        backend: request.backend,
        lifecycle: :thinking,
        provider: provider,
        content: text,
        metadata: execution_metadata(provider, session_id)
      })
    )
  end

  defp emit_terminal_event(request, emit_event, %Result{status: :completed} = result, state) do
    emit_event_safe(
      emit_event,
      Event.new!(%{
        request_id: request.request_id,
        conversation_id: request.conversation_id,
        backend: request.backend,
        lifecycle: :completed,
        content: result.text,
        provider: result.provider,
        finish_reason: result.finish_reason,
        usage: result.usage,
        metadata: %{
          session_id: state.session_id,
          execution_ref: execution_ref(state.provider, state.session_id),
          event_count: state.event_count,
          status: :completed
        }
      })
    )
  end

  defp emit_terminal_event(request, emit_event, %Result{status: :canceled} = result, state) do
    emit_event_safe(
      emit_event,
      Event.new!(%{
        request_id: request.request_id,
        conversation_id: request.conversation_id,
        backend: request.backend,
        lifecycle: :canceled,
        provider: result.provider,
        finish_reason: result.finish_reason,
        usage: result.usage,
        metadata: %{
          session_id: state.session_id,
          execution_ref: execution_ref(state.provider, state.session_id),
          event_count: state.event_count,
          status: :canceled
        }
      })
    )
  end

  defp emit_terminal_event(_request, _emit_event, %Result{}, _state), do: :ok

  defp emit_failed_event(%Request{} = request, emit_event, %Error{} = error) do
    emit_event_safe(
      emit_event,
      Event.new!(%{
        request_id: request.request_id,
        conversation_id: request.conversation_id,
        backend: request.backend,
        lifecycle: :failed,
        error: error
      })
    )
  end

  defp execution_metadata(provider, session_id) do
    %{
      session_id: session_id,
      execution_ref: execution_ref(provider, session_id)
    }
    |> compact_map()
  end

  defp execution_ref(provider, session_id) when is_binary(session_id) and session_id != "" do
    %{provider: provider, session_id: session_id}
  end

  defp execution_ref(_provider, _session_id), do: nil

  defp emit_event_safe(emit_event, %Event{} = event) do
    _ = emit_event.(event)
    :ok
  rescue
    _ -> :ok
  catch
    _, _ -> :ok
  end

  defp init_state(invocation) do
    %{
      provider: invocation.provider,
      session_id: nil,
      status: :completed,
      text_chunks: [],
      thinking_chunks: [],
      final_text: nil,
      finish_reason: nil,
      usage: %{},
      error: nil,
      event_count: 0
    }
  end

  defp build_result(%Request{} = request, state) do
    text =
      first_non_nil([
        state.final_text,
        state.text_chunks |> Enum.reverse() |> Enum.join("")
      ]) || ""

    result =
      Result.new!(%{
        request_id: request.request_id,
        conversation_id: request.conversation_id,
        backend: request.backend,
        status: state.status,
        text: text,
        provider: state.provider,
        finish_reason: state.finish_reason,
        usage: state.usage,
        metadata: %{
          session_id: state.session_id,
          thinking: state.thinking_chunks |> Enum.reverse() |> Enum.join("\n\n"),
          event_count: state.event_count
        },
        error: state.error
      })

    {:ok, result}
  rescue
    error ->
      {:error, normalize_error(error)}
  end

  defp build_prompt(%Request{} = request) do
    prompt_parts =
      []
      |> maybe_prepend_system_prompt(request.system_prompt)
      |> Kernel.++(Enum.map(request.messages, &message_to_prompt_line/1))
      |> Enum.reject(&(&1 == ""))

    case prompt_parts do
      [] ->
        {:error,
         Error.new!(
           category: :config,
           message: "harness request cannot be built from empty messages"
         )}

      parts ->
        {:ok, Enum.join(parts, "\n\n")}
    end
  end

  defp maybe_prepend_system_prompt(parts, system_prompt) when is_binary(system_prompt) do
    case String.trim(system_prompt) do
      "" -> parts
      prompt -> ["System:\n#{prompt}" | parts]
    end
  end

  defp maybe_prepend_system_prompt(parts, _), do: parts

  defp message_to_prompt_line(message) when is_map(message) do
    role =
      message
      |> get_field(:role)
      |> normalize_role()

    content =
      message
      |> get_field(:content)
      |> content_to_text()

    case String.trim(content) do
      "" -> ""
      text -> "#{role}:\n#{text}"
    end
  end

  defp message_to_prompt_line(_), do: ""

  defp build_run_opts(%Request{} = request) do
    with {:ok, option_overrides} <- options_to_keyword(request.options) do
      metadata =
        request.metadata
        |> normalize_map()
        |> Map.merge(normalize_map(Keyword.get(option_overrides, :metadata)))

      opts =
        option_overrides
        |> Keyword.put(:metadata, metadata)
        |> put_new_opt(:timeout_ms, request.timeout_ms)
        |> put_new_opt(:system_prompt, request.system_prompt)

      {:ok, opts}
    end
  end

  defp options_to_keyword(nil), do: {:ok, []}

  defp options_to_keyword(options) when is_map(options) do
    mapped =
      Enum.reduce(options, [], fn
        {key, value}, acc when is_atom(key) ->
          [{key, value} | acc]

        {key, value}, acc when is_binary(key) ->
          case Map.fetch(@mapped_string_options, key) do
            {:ok, mapped_key} -> [{mapped_key, value} | acc]
            :error -> acc
          end

        {_key, _value}, acc ->
          acc
      end)
      |> Enum.reverse()

    {:ok, mapped}
  end

  defp options_to_keyword(other) do
    {:error,
     Error.new!(
       category: :config,
       message: "invalid request options payload for harness adapter",
       details: %{options: other}
     )}
  end

  defp resolve_harness_provider(run_opts, adapter_opts) do
    candidate =
      first_non_nil([
        Keyword.get(adapter_opts, :harness_provider),
        Keyword.get(adapter_opts, :provider),
        Keyword.get(run_opts, :harness_provider),
        Keyword.get(run_opts, :provider)
      ])

    normalize_harness_provider(candidate)
  end

  defp normalize_harness_provider(nil), do: {:ok, nil}
  defp normalize_harness_provider(provider) when is_atom(provider), do: {:ok, provider}

  defp normalize_harness_provider(provider) when is_binary(provider) do
    provider = provider |> String.trim() |> String.downcase()

    case Map.fetch(@known_harness_providers, provider) do
      {:ok, atom_provider} ->
        {:ok, atom_provider}

      :error ->
        {:error,
         Error.new!(
           category: :config,
           message: "unknown harness provider string",
           details: %{provider: provider}
         )}
    end
  end

  defp normalize_harness_provider(other) do
    {:error,
     Error.new!(
       category: :config,
       message: "invalid harness provider value",
       details: %{provider: other}
     )}
  end

  defp normalize_harness_event(raw_event, fallback_provider) do
    event = to_plain_map(raw_event)
    payload = extract_payload(event)
    type = infer_event_type(event, payload)

    %{
      type: type,
      type_name: canonical_type(type),
      provider:
        first_non_nil([
          normalize_identifier(get_field(event, :provider)),
          normalize_identifier(get_field(payload, :provider)),
          normalize_identifier(fallback_provider)
        ]),
      session_id:
        first_non_nil([
          normalize_identifier(get_field(event, :session_id)),
          normalize_identifier(get_field(payload, :session_id)),
          normalize_identifier(get_field(event, :thread_id)),
          normalize_identifier(get_field(payload, :thread_id))
        ]),
      payload: payload,
      raw: raw_event
    }
  end

  defp infer_event_type(event, payload) do
    first_non_nil([
      get_field(event, :type),
      get_field(payload, :type),
      infer_type_from_payload(payload),
      :provider_event
    ])
  end

  defp infer_type_from_payload(payload) when is_map(payload) do
    cond do
      is_binary(get_field(payload, :output_text)) -> :output_text_final
      is_binary(get_field(payload, :text)) -> :output_text_delta
      not is_nil(get_field(payload, :error)) -> :session_failed
      true -> nil
    end
  end

  defp extract_payload(event) when is_map(event) do
    case get_field(event, :payload) do
      %{} = payload ->
        payload

      _ ->
        event
        |> Map.drop([:type, :provider, :session_id, :timestamp, :raw, "__struct__"])
        |> normalize_map()
    end
  end

  defp extract_delta_chunks(event) do
    text_chunks = []

    text_chunks =
      if delta_event?(event) do
        text_chunks ++
          text_candidates(event.payload) ++
          text_candidates(event.raw) ++
          assistant_content_chunks(event.payload, :text) ++
          assistant_content_chunks(event.raw, :text)
      else
        text_chunks
      end

    text_chunks
    |> Enum.reject(&(String.trim(&1) == ""))
    |> Enum.uniq()
  end

  defp extract_thinking_chunks(event) do
    thinking_chunks = []

    thinking_chunks =
      if thinking_event?(event) or canonical_type(event.type) == "assistant" do
        thinking_chunks ++
          thinking_candidates(event.payload) ++
          thinking_candidates(event.raw) ++
          assistant_content_chunks(event.payload, :thinking) ++
          assistant_content_chunks(event.raw, :thinking)
      else
        thinking_chunks
      end

    thinking_chunks
    |> Enum.reject(&(String.trim(&1) == ""))
    |> Enum.uniq()
  end

  defp extract_final_text_candidate(event) do
    if completed_event?(event) or canonical_type(event.type) == "output_text_final" do
      first_non_nil([
        final_text_from(normalize_map(event.payload)),
        final_text_from(normalize_map(event.raw))
      ])
    else
      nil
    end
  end

  defp extract_usage(event) do
    usage =
      first_non_nil([
        get_field(event.payload, :usage),
        get_field(event.raw, :usage),
        get_field(event.payload, :token_usage),
        get_field(event.raw, :token_usage)
      ])

    usage
    |> normalize_usage()
  end

  defp extract_finish_reason(event) do
    first_non_nil([
      normalize_finish_reason(get_field(event.payload, :finish_reason)),
      normalize_finish_reason(get_field(event.raw, :finish_reason)),
      normalize_finish_reason(get_field(event.payload, :stop_reason)),
      normalize_finish_reason(get_field(event.raw, :stop_reason))
    ])
  end

  defp normalize_failed_event(event) do
    reason =
      first_non_nil([
        get_field(event.payload, :error),
        get_field(event.raw, :error),
        get_field(event.payload, :message),
        get_field(event.raw, :message),
        event.raw
      ])

    error = normalize_error(reason)

    case error.category do
      :unknown ->
        Error.from_reason(reason, :provider, message: error.message)

      _ ->
        error
    end
  end

  defp completed_event?(event) do
    type = canonical_type(event.type)

    type in ["session_completed", "completed", "turn_completed"] or
      (type == "result" and not result_error?(event))
  end

  defp failed_event?(event) do
    type = canonical_type(event.type)

    type in ["session_failed", "failed", "error", "turn_failed"] or
      (type == "result" and result_error?(event))
  end

  defp canceled_event?(event) do
    canonical_type(event.type) in [
      "session_cancelled",
      "session_canceled",
      "cancelled",
      "canceled",
      "turn_aborted"
    ]
  end

  defp delta_event?(event) do
    canonical_type(event.type) in [
      "output_text_delta",
      "text_delta",
      "delta",
      "assistant_text",
      "assistant",
      "output_text_final"
    ]
  end

  defp thinking_event?(event) do
    canonical_type(event.type) in ["thinking_delta", "thinking"]
  end

  defp result_error?(event) do
    payload = normalize_map(event.payload)
    raw = normalize_map(event.raw)

    is_error =
      first_non_nil([
        get_field(payload, :is_error),
        get_field(raw, :is_error)
      ])

    subtype =
      first_non_nil([
        get_field(payload, :subtype),
        get_field(raw, :subtype)
      ])

    status =
      first_non_nil([
        get_field(payload, :status),
        get_field(raw, :status)
      ])

    error_flag?(is_error) or
      error_subtype?(subtype) or
      error_status?(status) or
      not is_nil(get_field(payload, :error))
  end

  defp error_flag?(value) when is_boolean(value), do: value
  defp error_flag?(_), do: false

  defp error_subtype?(value) when is_binary(value) do
    value
    |> String.downcase()
    |> String.starts_with?("error")
  end

  defp error_subtype?(value) when is_atom(value) do
    value
    |> Atom.to_string()
    |> String.starts_with?("error")
  end

  defp error_subtype?(_), do: false

  defp error_status?(value) when is_binary(value) do
    String.downcase(value) in ["error", "failed", "failure"]
  end

  defp error_status?(value) when is_atom(value) do
    value in [:error, :failed, :failure]
  end

  defp error_status?(_), do: false

  defp final_text_from(value) when is_map(value) do
    first_non_nil([
      text_from_field(get_field(value, :output_text)),
      text_from_field(get_field(value, :text)),
      text_from_field(get_field(value, :content)),
      text_from_field(get_field(value, :result)),
      assistant_blocks_to_text(get_nested_field(value, [:message, :content]))
    ])
  end

  defp text_candidates(value) when is_map(value) do
    [
      text_from_field(get_field(value, :delta)),
      text_from_field(get_field(value, :text)),
      text_from_field(get_field(value, :output_text))
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp text_candidates(_), do: []

  defp thinking_candidates(value) when is_map(value) do
    [
      text_from_field(get_field(value, :text)),
      text_from_field(get_field(value, :thinking)),
      text_from_field(get_field(value, :reasoning))
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp thinking_candidates(_), do: []

  defp assistant_content_chunks(value, chunk_type) when chunk_type in [:text, :thinking] do
    value
    |> normalize_map()
    |> get_nested_field([:message, :content])
    |> extract_assistant_chunks(chunk_type)
  end

  defp assistant_content_chunks(_value, _chunk_type), do: []

  defp extract_assistant_chunks(content, chunk_type) when is_list(content) do
    Enum.flat_map(content, &extract_assistant_chunk(&1, chunk_type))
  end

  defp extract_assistant_chunks(_content, _chunk_type), do: []

  defp extract_assistant_chunk(%{} = block, chunk_type) do
    block
    |> chunk_value(chunk_type)
    |> wrap_chunk()
  end

  defp extract_assistant_chunk(_block, _chunk_type), do: []

  defp chunk_value(block, :text) do
    if canonical_type(get_field(block, :type)) == "text" do
      text_from_field(get_field(block, :text))
    end
  end

  defp chunk_value(block, :thinking) do
    if canonical_type(get_field(block, :type)) == "thinking" do
      text_from_field(get_field(block, :thinking))
    end
  end

  defp wrap_chunk(nil), do: []
  defp wrap_chunk(text), do: [text]

  defp assistant_blocks_to_text(content) do
    content
    |> extract_assistant_chunks(:text)
    |> case do
      [] -> nil
      chunks -> Enum.join(chunks, "")
    end
  end

  defp text_from_field(nil), do: nil
  defp text_from_field(value) when is_binary(value), do: value
  defp text_from_field(value) when is_list(value), do: iodata_to_text(value)
  defp text_from_field(_), do: nil

  defp content_to_text(nil), do: ""
  defp content_to_text(value) when is_binary(value), do: value
  defp content_to_text(value) when is_list(value), do: iodata_to_text(value)

  defp content_to_text(value) when is_map(value) do
    first_non_nil([
      assistant_blocks_to_text(get_nested_field(value, [:message, :content])),
      text_from_field(get_field(value, :text)),
      text_from_field(get_field(value, :content))
    ]) || ""
  end

  defp content_to_text(value), do: inspect(value)

  defp normalize_usage(%{} = usage) do
    input_tokens = number_field(usage, :input_tokens)
    output_tokens = number_field(usage, :output_tokens)
    total_tokens = number_field(usage, :total_tokens)

    %{
      input_tokens: input_tokens || 0,
      output_tokens: output_tokens || 0,
      total_tokens: total_tokens || (input_tokens || 0) + (output_tokens || 0),
      cache_creation_input_tokens: number_field(usage, :cache_creation_input_tokens),
      cache_read_input_tokens: number_field(usage, :cache_read_input_tokens)
    }
    |> compact_map()
  end

  defp normalize_usage(_), do: %{}

  defp number_field(map, key) when is_map(map) do
    value = get_field(map, key)

    cond do
      is_integer(value) ->
        value

      is_float(value) ->
        value

      is_binary(value) ->
        case Float.parse(value) do
          {parsed, ""} -> parsed
          _ -> nil
        end

      true ->
        nil
    end
  end

  defp normalize_finish_reason(nil), do: nil
  defp normalize_finish_reason(value) when is_binary(value), do: value
  defp normalize_finish_reason(value) when is_atom(value), do: value
  defp normalize_finish_reason(_), do: nil

  defp resolve_cancel_provider(execution_ref, opts) do
    candidate =
      first_non_nil([
        get_field(normalize_map(execution_ref), :provider),
        Keyword.get(opts, :provider),
        Keyword.get(opts, :harness_provider)
      ])

    normalize_harness_provider(candidate)
  end

  defp resolve_cancel_session_id(execution_ref, opts) do
    session_id =
      first_non_nil([
        normalize_identifier(get_field(normalize_map(execution_ref), :session_id)),
        normalize_identifier(get_field(normalize_map(execution_ref), :id)),
        normalize_identifier(Keyword.get(opts, :session_id))
      ])

    case session_id do
      nil ->
        {:error,
         Error.new!(
           category: :config,
           message: "missing harness session_id for cancellation"
         )}

      value ->
        {:ok, value}
    end
  end

  defp validate_cancel_response(:ok), do: :ok

  defp validate_cancel_response({:ok, _value}), do: :ok

  defp validate_cancel_response({:error, reason}), do: {:error, normalize_error(reason)}

  defp validate_cancel_response(other) do
    {:error,
     Error.new!(
       category: :provider,
       message: "harness cancellation returned an invalid response",
       details: %{response: other}
     )}
  end

  defp harness_module(opts) do
    Keyword.get(opts, :harness_module, @default_harness_module)
  end

  defp ensure_function(module, function, arity) when is_atom(module) do
    case Code.ensure_loaded?(module) do
      false ->
        {:error,
         Error.new!(
           category: :config,
           message: "required module is not available",
           details: %{module: module, function: function, arity: arity}
         )}

      true ->
        case function_exported?(module, function, arity) do
          true ->
            :ok

          false ->
            {:error,
             Error.new!(
               category: :config,
               message: "required function is not exported",
               details: %{module: module, function: function, arity: arity}
             )}
        end
    end
  end

  defp invoke_plain(module, function, args) do
    {:ok, apply(module, function, args)}
  rescue
    error ->
      {:error, error}
  catch
    kind, reason ->
      {:error, {kind, reason}}
  end

  defp normalize_error(%Error{} = error), do: error
  defp normalize_error({:error, reason}), do: normalize_error(reason)

  defp normalize_error(%{status: status} = reason) when status in [401, 403] do
    Error.from_reason(reason, :auth, message: extract_error_message(reason))
  end

  defp normalize_error(%{status: status} = reason) when status == 408 do
    Error.from_reason(reason, :timeout, message: extract_error_message(reason))
  end

  defp normalize_error(%{status: status} = reason) when is_integer(status) and status >= 400 do
    Error.from_reason(reason, :provider, message: extract_error_message(reason))
  end

  defp normalize_error(%{reason: reason} = error) when reason in @timeout_reasons do
    Error.from_reason(error, :timeout, message: extract_error_message(error))
  end

  defp normalize_error(%{reason: reason} = error) when reason in @network_reasons do
    Error.from_reason(error, :transport, message: extract_error_message(error))
  end

  defp normalize_error(reason) when reason in @timeout_reasons do
    Error.from_reason(reason, :timeout, message: extract_error_message(reason))
  end

  defp normalize_error(reason) when reason in @network_reasons do
    Error.from_reason(reason, :transport, message: extract_error_message(reason))
  end

  defp normalize_error(reason) when reason in [:canceled, :cancelled] do
    Error.from_reason(reason, :canceled, message: extract_error_message(reason))
  end

  defp normalize_error(%RuntimeError{} = error) do
    Error.from_reason(error, :unknown, message: Exception.message(error))
  end

  defp normalize_error(%ArgumentError{} = error) do
    Error.from_reason(error, :config, message: Exception.message(error))
  end

  defp normalize_error(error) do
    Error.from_reason(error, :unknown, message: extract_error_message(error))
  end

  defp extract_error_message(%{message: message}) when is_binary(message), do: message
  defp extract_error_message({kind, reason}), do: "#{inspect(kind)}: #{inspect(reason)}"
  defp extract_error_message(error) when is_binary(error), do: error
  defp extract_error_message(error) when is_atom(error), do: Atom.to_string(error)
  defp extract_error_message(error), do: inspect(error)

  defp normalize_role(role) when is_atom(role),
    do: role |> Atom.to_string() |> String.capitalize()

  defp normalize_role(role) when is_binary(role) do
    role
    |> String.trim()
    |> String.downcase()
    |> case do
      "" -> "User"
      normalized -> String.capitalize(normalized)
    end
  end

  defp normalize_role(_), do: "User"

  defp canonical_type(type) when is_atom(type), do: type |> Atom.to_string() |> canonical_type()

  defp canonical_type(type) when is_binary(type) do
    type
    |> String.trim()
    |> String.downcase()
    |> String.replace("-", "_")
  end

  defp canonical_type(_), do: "provider_event"

  defp normalize_map(nil), do: %{}
  defp normalize_map(%{} = map), do: map
  defp normalize_map(list) when is_list(list), do: Enum.into(list, %{})
  defp normalize_map(_), do: %{}

  defp normalize_identifier(nil), do: nil
  defp normalize_identifier(value) when is_atom(value), do: value

  defp normalize_identifier(value) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: nil, else: value
  end

  defp normalize_identifier(_), do: nil

  defp to_plain_map(%_{} = struct), do: struct |> Map.from_struct()
  defp to_plain_map(%{} = map), do: map
  defp to_plain_map(_), do: %{}

  defp get_field(map, key) when is_map(map) do
    case Map.fetch(map, key) do
      {:ok, value} ->
        value

      :error ->
        case Map.fetch(map, to_string(key)) do
          {:ok, value} -> value
          :error -> nil
        end
    end
  end

  defp get_nested_field(value, []), do: value

  defp get_nested_field(map, [key | rest]) when is_map(map) do
    map
    |> get_field(key)
    |> get_nested_field(rest)
  end

  defp get_nested_field(_value, _path), do: nil

  defp put_new_opt(opts, _key, nil), do: opts

  defp put_new_opt(opts, key, value) do
    if Keyword.has_key?(opts, key) do
      opts
    else
      Keyword.put(opts, key, value)
    end
  end

  defp first_non_nil(values) when is_list(values) do
    Enum.find(values, &(not is_nil(&1)))
  end

  defp compact_map(map) do
    Enum.reduce(map, %{}, fn
      {_key, nil}, acc ->
        acc

      {key, value}, acc ->
        Map.put(acc, key, value)
    end)
  end

  defp iodata_to_text(content) do
    IO.iodata_to_binary(content)
  rescue
    _ -> nil
  catch
    _, _ -> nil
  end
end
