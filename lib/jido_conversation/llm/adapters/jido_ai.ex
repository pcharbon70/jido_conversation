defmodule JidoConversation.LLM.Adapters.JidoAI do
  @moduledoc """
  `JidoAI` backend adapter for the unified LLM client contract.

  This adapter intentionally calls `Jido.AI` and `Jido.AI.LLMClient` dynamically
  so `jido_conversation` can compile without requiring `jido_ai` as a direct
  dependency in all environments.
  """

  @behaviour JidoConversation.LLM.Backend

  alias JidoConversation.LLM.Error
  alias JidoConversation.LLM.Event
  alias JidoConversation.LLM.Request
  alias JidoConversation.LLM.Result

  @default_jido_ai_module Jido.AI
  @default_llm_client_module Jido.AI.LLMClient

  @network_reasons [:econnrefused, :nxdomain, :closed, :enetdown, :ehostunreach]
  @timeout_reasons [:timeout, :connect_timeout, :checkout_timeout, :receive_timeout]

  @impl true
  def capabilities do
    %{
      streaming?: true,
      cancellation?: cancellation_supported?(),
      provider_selection?: true,
      model_selection?: true
    }
  end

  @impl true
  def start(%Request{} = request, opts) when is_list(opts) do
    with {:ok, model_spec} <- resolve_model_spec(request, opts),
         {:ok, messages} <- build_messages(request),
         {:ok, request_opts} <- build_request_opts(request),
         llm_context = llm_client_context(opts),
         llm_client_module = llm_client_module(opts),
         {:ok, response} <-
           invoke_llm_client(llm_client_module, :generate_text, [
             llm_context,
             model_spec,
             messages,
             request_opts
           ]),
         {:ok, response} <- ensure_response_map(response) do
      {:ok, build_result(request, response, model_spec, :completed)}
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
    with {:ok, model_spec} <- resolve_model_spec(request, opts),
         {:ok, messages} <- build_messages(request),
         {:ok, request_opts} <- build_request_opts(request),
         llm_context = llm_client_context(opts),
         llm_client_module = llm_client_module(opts),
         {:ok, stream_response} <-
           invoke_llm_client(llm_client_module, :stream_text, [
             llm_context,
             model_spec,
             messages,
             request_opts
           ]),
         :ok <- emit_started_event(request, emit_event, model_spec, stream_response),
         {:ok, response} <-
           invoke_llm_client(llm_client_module, :process_stream, [
             llm_context,
             stream_response,
             stream_processing_opts(request, emit_event, model_spec)
           ]),
         {:ok, response} <- ensure_response_map(response) do
      result = build_result(request, response, model_spec, :completed)
      _ = emit_completed_event(request, emit_event, model_spec, result, response)
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
    llm_client_module = llm_client_module(opts)

    with {:ok, cancel_ref} <- normalize_execution_ref(execution_ref),
         :ok <- ensure_function(llm_client_module, :cancel, 1),
         {:ok, response} <- invoke_plain(llm_client_module, :cancel, [cancel_ref]) do
      normalize_cancel_response(response)
    else
      {:error, %Error{} = error} ->
        {:error, error}

      {:error, reason} ->
        {:error, normalize_error(reason)}
    end
  end

  defp cancellation_supported? do
    function_exported?(@default_llm_client_module, :cancel, 1)
  end

  defp normalize_execution_ref(nil) do
    {:error,
     Error.new!(
       category: :config,
       message: "missing execution_ref for jido_ai cancellation"
     )}
  end

  defp normalize_execution_ref(execution_ref), do: {:ok, execution_ref}

  defp normalize_cancel_response(:ok), do: :ok
  defp normalize_cancel_response({:ok, _value}), do: :ok

  defp normalize_cancel_response({:error, reason}) do
    {:error, normalize_error(reason)}
  end

  defp normalize_cancel_response(other) do
    {:error,
     Error.new!(
       category: :provider,
       message: "jido_ai cancellation returned an invalid response",
       details: %{response: other}
     )}
  end

  defp stream_processing_opts(request, emit_event, model_spec) do
    [
      on_result: fn chunk ->
        emit_chunk_event(request, emit_event, model_spec, :delta, chunk)
      end,
      on_thinking: fn chunk ->
        emit_chunk_event(request, emit_event, model_spec, :thinking, chunk)
      end
    ]
  end

  defp emit_started_event(request, emit_event, model_spec, execution_ref) do
    emit_event_safe(
      emit_event,
      Event.new!(%{
        request_id: request.request_id,
        conversation_id: request.conversation_id,
        backend: request.backend,
        lifecycle: :started,
        model: model_spec,
        provider: resolved_provider(request, model_spec),
        metadata: %{
          stream?: request.stream?,
          timeout_ms: request.timeout_ms,
          execution_ref: execution_ref
        }
      })
    )
  end

  defp emit_chunk_event(request, emit_event, model_spec, lifecycle, chunk)
       when lifecycle in [:delta, :thinking] do
    case normalize_chunk(chunk) do
      nil ->
        :ok

      text ->
        event_data = %{
          request_id: request.request_id,
          conversation_id: request.conversation_id,
          backend: request.backend,
          lifecycle: lifecycle,
          model: model_spec,
          provider: resolved_provider(request, model_spec),
          metadata: %{}
        }

        event_data =
          case lifecycle do
            :delta -> Map.put(event_data, :delta, text)
            :thinking -> Map.put(event_data, :content, text)
          end

        emit_event_safe(emit_event, Event.new!(event_data))
    end
  end

  defp normalize_chunk(text) when is_binary(text) do
    case String.trim(text) do
      "" -> nil
      _ -> text
    end
  end

  defp normalize_chunk(_), do: nil

  defp emit_completed_event(request, emit_event, model_spec, %Result{} = result, response) do
    emit_event_safe(
      emit_event,
      Event.new!(%{
        request_id: request.request_id,
        conversation_id: request.conversation_id,
        backend: request.backend,
        lifecycle: :completed,
        content: result.text,
        model: result.model || model_spec,
        provider: result.provider,
        finish_reason: result.finish_reason,
        usage: result.usage,
        metadata:
          build_response_metadata(response, model_spec)
          |> Map.put(:status, :completed)
      })
    )
  end

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

  defp emit_event_safe(emit_event, %Event{} = event) do
    _ = emit_event.(event)
    :ok
  rescue
    _ -> :ok
  catch
    _, _ -> :ok
  end

  defp build_result(%Request{} = request, response, model_spec, status)
       when status in [:completed, :canceled] do
    Result.new!(%{
      request_id: request.request_id,
      conversation_id: request.conversation_id,
      backend: request.backend,
      status: status,
      text: extract_text(response),
      model: resolved_model(response, model_spec),
      provider: resolved_provider(request, model_spec),
      finish_reason: normalize_finish_reason(get_field(response, :finish_reason)),
      usage: normalize_usage(get_field(response, :usage)),
      metadata: build_response_metadata(response, model_spec)
    })
  end

  defp build_messages(%Request{} = request) do
    normalized =
      request.messages
      |> Enum.map(&normalize_message/1)

    messages =
      case request.system_prompt do
        system_prompt when is_binary(system_prompt) ->
          [%{role: :system, content: system_prompt} | normalized]

        _ ->
          normalized
      end

    {:ok, messages}
  end

  defp normalize_message(message) when is_map(message) do
    role = normalize_role(get_field(message, :role))
    content = get_field(message, :content)

    extras = Map.drop(message, [:role, "role", :content, "content"])

    %{role: role, content: content}
    |> Map.merge(extras)
  end

  defp normalize_message(_message) do
    %{
      role: :user,
      content: ""
    }
  end

  defp normalize_role(role) when is_atom(role), do: role

  defp normalize_role(role) when is_binary(role) do
    normalized = role |> String.trim() |> String.downcase()

    case normalized do
      "system" -> :system
      "user" -> :user
      "assistant" -> :assistant
      "tool" -> :tool
      _ when normalized != "" -> normalized
      _ -> :user
    end
  end

  defp normalize_role(_), do: :user

  defp build_request_opts(%Request{} = request) do
    with {:ok, option_overrides} <- options_to_keyword(request.options) do
      opts =
        []
        |> Keyword.merge(option_overrides)
        |> put_opt(:max_tokens, request.max_tokens)
        |> put_opt(:temperature, request.temperature)
        |> put_opt(:receive_timeout, request.timeout_ms)

      {:ok, opts}
    end
  end

  defp options_to_keyword(nil), do: {:ok, []}

  defp options_to_keyword(opts) when is_map(opts) do
    mapped =
      Enum.reduce(opts, [], fn
        {key, value}, acc when is_atom(key) ->
          [{key, value} | acc]

        {"max_tokens", value}, acc ->
          [{:max_tokens, value} | acc]

        {"temperature", value}, acc ->
          [{:temperature, value} | acc]

        {"timeout_ms", value}, acc ->
          [{:receive_timeout, value} | acc]

        {"receive_timeout", value}, acc ->
          [{:receive_timeout, value} | acc]

        {"tools", value}, acc ->
          [{:tools, value} | acc]

        {"tool_choice", value}, acc ->
          [{:tool_choice, value} | acc]

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
       message: "invalid request options payload for jido_ai adapter",
       details: %{options: other}
     )}
  end

  defp put_opt(opts, _key, nil), do: opts
  defp put_opt(opts, key, value), do: Keyword.put(opts, key, value)

  defp resolve_model_spec(%Request{} = request, opts) do
    provider = normalize_identifier(request.provider)

    case request.model do
      model when is_binary(model) and model != "" ->
        {:ok, join_provider_and_model(provider, model)}

      model_alias when is_atom(model_alias) ->
        with {:ok, resolved} <- resolve_model_alias(model_alias, opts) do
          {:ok, maybe_rewrite_provider(resolved, provider)}
        end

      nil ->
        with {:ok, fallback} <- resolve_model_alias(:fast, opts) do
          {:ok, maybe_rewrite_provider(fallback, provider)}
        end

      other ->
        {:error,
         Error.new!(
           category: :config,
           message: "unsupported model value for jido_ai adapter",
           details: %{model: other}
         )}
    end
  end

  defp resolve_model_alias(model_alias, opts) do
    jido_ai_module = jido_ai_module(opts)

    with :ok <- ensure_function(jido_ai_module, :resolve_model, 1),
         {:ok, resolved} <- invoke_plain(jido_ai_module, :resolve_model, [model_alias]) do
      validate_resolved_model_spec(resolved, model_alias)
    end
  end

  defp validate_resolved_model_spec(value, _model_alias) when is_binary(value) do
    case String.trim(value) do
      "" ->
        {:error,
         Error.new!(
           category: :config,
           message: "jido_ai model alias resolution returned an invalid model spec",
           details: %{resolved: value}
         )}

      _ ->
        {:ok, value}
    end
  end

  defp validate_resolved_model_spec(value, model_alias) do
    {:error,
     Error.new!(
       category: :config,
       message: "jido_ai model alias resolution returned an invalid model spec",
       details: %{alias: model_alias, resolved: value}
     )}
  end

  defp invoke_llm_client(module, function, args) do
    with :ok <- ensure_function(module, function, length(args)),
         {:ok, response} <- invoke_plain(module, function, args),
         :ok <- validate_llm_tuple(response) do
      response
    end
  end

  defp validate_llm_tuple({:ok, _response}), do: :ok
  defp validate_llm_tuple({:error, _reason}), do: :ok

  defp validate_llm_tuple(other) do
    {:error,
     Error.new!(
       category: :provider,
       message: "jido_ai llm client returned an invalid response tuple",
       details: %{response: other}
     )}
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

  defp ensure_response_map(response) when is_map(response), do: {:ok, response}

  defp ensure_response_map(response) do
    {:error,
     Error.new!(
       category: :provider,
       message: "jido_ai llm client returned a non-map response payload",
       details: %{response: response}
     )}
  end

  defp jido_ai_module(opts) do
    Keyword.get(opts, :jido_ai_module, @default_jido_ai_module)
  end

  defp llm_client_module(opts) do
    Keyword.get(opts, :llm_client_module, @default_llm_client_module)
  end

  defp llm_client_context(opts) do
    base_context =
      case Keyword.get(opts, :llm_client_context, %{}) do
        %{} = context -> context
        context when is_list(context) -> Enum.into(context, %{})
        _ -> %{}
      end

    case Keyword.get(opts, :llm_client) do
      module when is_atom(module) -> Map.put(base_context, :llm_client, module)
      _ -> base_context
    end
  end

  defp extract_text(response) when is_map(response) do
    content =
      first_non_nil([
        get_nested_field(response, [:message, :content]),
        get_nested_field(response, ["message", "content"]),
        get_nested_field(response, [:choices, 0, :message, :content]),
        get_nested_field(response, ["choices", 0, "message", "content"]),
        get_field(response, :content)
      ])

    content_to_text(content)
  end

  defp content_to_text(nil), do: ""
  defp content_to_text(content) when is_binary(content), do: content

  defp content_to_text([%{} | _] = content) do
    content
    |> Enum.flat_map(fn
      %{type: :text, text: text} when is_binary(text) -> [text]
      %{"type" => "text", "text" => text} when is_binary(text) -> [text]
      _ -> []
    end)
    |> Enum.join("\n")
  end

  defp content_to_text(content) when is_list(content), do: iodata_to_text(content)

  defp content_to_text(_), do: ""

  defp extract_thinking(response) when is_map(response) do
    case get_nested_field(response, [:message, :content]) ||
           get_nested_field(response, ["message", "content"]) do
      content when is_list(content) ->
        content
        |> Enum.flat_map(fn
          %{type: :thinking, thinking: thinking} when is_binary(thinking) -> [thinking]
          %{"type" => "thinking", "thinking" => thinking} when is_binary(thinking) -> [thinking]
          _ -> []
        end)
        |> Enum.join("\n\n")
        |> case do
          "" -> nil
          text -> text
        end

      _ ->
        nil
    end
  end

  defp extract_tool_calls(response) when is_map(response) do
    case get_nested_field(response, [:message, :tool_calls]) ||
           get_nested_field(response, ["message", "tool_calls"]) do
      tool_calls when is_list(tool_calls) -> tool_calls
      _ -> []
    end
  end

  defp build_response_metadata(response, model_spec) when is_map(response) do
    tool_calls = extract_tool_calls(response)
    thinking = extract_thinking(response)

    %{
      resolved_model_spec: model_spec,
      tool_calls: tool_calls,
      tool_call_count: length(tool_calls),
      thinking: thinking
    }
    |> compact_map()
  end

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

  defp number_field(map, key) do
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

  defp resolved_model(response, model_spec) do
    case get_field(response, :model) do
      value when is_binary(value) and value != "" -> value
      value when is_atom(value) -> value
      _ -> model_spec
    end
  end

  defp resolved_provider(%Request{} = request, model_spec) do
    normalize_identifier(request.provider) || model_provider(model_spec)
  end

  defp model_provider(model_spec) when is_binary(model_spec) do
    case String.split(model_spec, ":", parts: 2) do
      [provider, _model] when provider != "" -> provider
      _ -> nil
    end
  end

  defp maybe_rewrite_provider(model_spec, nil), do: model_spec

  defp maybe_rewrite_provider(model_spec, provider)
       when is_binary(model_spec) and is_binary(provider) do
    model_name =
      case String.split(model_spec, ":", parts: 2) do
        [_provider, model] -> model
        [model] -> model
      end

    join_provider_and_model(provider, model_name)
  end

  defp maybe_rewrite_provider(model_spec, _provider), do: model_spec

  defp join_provider_and_model(nil, model), do: model

  defp join_provider_and_model(provider, model) when is_binary(model) do
    model = String.trim(model)

    cond do
      model == "" ->
        model

      String.contains?(model, ":") ->
        model

      provider != "" ->
        "#{provider}:#{model}"

      true ->
        model
    end
  end

  defp normalize_identifier(nil), do: nil
  defp normalize_identifier(value) when is_atom(value), do: Atom.to_string(value)

  defp normalize_identifier(value) when is_binary(value) do
    value = String.trim(value)

    case value do
      "" -> nil
      _ -> value
    end
  end

  defp normalize_identifier(_), do: nil

  defp normalize_finish_reason(nil), do: nil
  defp normalize_finish_reason(value) when is_binary(value), do: value
  defp normalize_finish_reason(value) when is_atom(value), do: value
  defp normalize_finish_reason(value), do: inspect(value)

  defp normalize_error(%Error{} = error), do: error
  defp normalize_error({:error, reason}), do: normalize_error(reason)

  defp normalize_error(%RuntimeError{} = error) do
    Error.from_reason(error, :unknown, message: Exception.message(error))
  end

  defp normalize_error(%ArgumentError{} = error) do
    Error.from_reason(error, :config, message: Exception.message(error))
  end

  defp normalize_error(%{} = error) do
    status = normalize_status_code(get_field(error, :status))
    reason = get_field(error, :reason)

    cond do
      status in [401, 403] ->
        Error.from_reason(error, :auth,
          message: extract_error_message(error),
          retryable?: false
        )

      status == 408 ->
        Error.from_reason(error, :timeout,
          message: extract_error_message(error),
          retryable?: true
        )

      is_integer(status) and status >= 400 ->
        Error.from_reason(error, :provider,
          message: extract_error_message(error),
          retryable?: retryable_provider_status?(status)
        )

      reason in @timeout_reasons ->
        Error.from_reason(error, :timeout, message: extract_error_message(error))

      reason in @network_reasons ->
        Error.from_reason(error, :transport, message: extract_error_message(error))

      true ->
        Error.from_reason(error, :unknown, message: extract_error_message(error))
    end
  end

  defp normalize_error(reason) when reason in @timeout_reasons do
    Error.from_reason(reason, :timeout, message: extract_error_message(reason))
  end

  defp normalize_error(reason) when reason in @network_reasons do
    Error.from_reason(reason, :transport, message: extract_error_message(reason))
  end

  defp normalize_error(error) do
    Error.from_reason(error, :unknown, message: extract_error_message(error))
  end

  defp normalize_status_code(status) when is_integer(status), do: status

  defp normalize_status_code(status) when is_binary(status) do
    case Integer.parse(String.trim(status)) do
      {parsed, ""} -> parsed
      _ -> nil
    end
  end

  defp normalize_status_code(_), do: nil

  # Retry only transient provider statuses.
  defp retryable_provider_status?(status)
       when status in [409, 425, 429] or (status >= 500 and status < 600),
       do: true

  defp retryable_provider_status?(_status), do: false

  defp extract_error_message(%{message: message}) when is_binary(message), do: message
  defp extract_error_message({kind, reason}), do: "#{inspect(kind)}: #{inspect(reason)}"
  defp extract_error_message(error) when is_binary(error), do: error
  defp extract_error_message(error) when is_atom(error), do: Atom.to_string(error)
  defp extract_error_message(error), do: inspect(error)

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

  defp get_nested_field(list, [index | rest]) when is_list(list) and is_integer(index) do
    list
    |> Enum.at(index)
    |> get_nested_field(rest)
  end

  defp get_nested_field(_value, _path), do: nil

  defp first_non_nil(values) when is_list(values) do
    Enum.find(values, &(not is_nil(&1)))
  end

  defp compact_map(map) do
    Enum.reduce(map, %{}, fn
      {_key, nil}, acc ->
        acc

      {:tool_calls, []}, acc ->
        acc

      {:tool_call_count, 0}, acc ->
        acc

      {key, value}, acc ->
        Map.put(acc, key, value)
    end)
  end

  defp iodata_to_text(content) do
    IO.iodata_to_binary(content)
  rescue
    _ -> ""
  catch
    _, _ -> ""
  end
end
