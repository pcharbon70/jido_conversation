defmodule Jido.Conversation.LLMGeneration do
  @moduledoc false

  alias Jido.Agent
  alias Jido.Conversation
  alias JidoConversation.Config
  alias JidoConversation.LLM.Error, as: LLMError
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

  @spec generate(Agent.t(), keyword()) ::
          {:ok, Agent.t(), LLMResult.t()} | {:error, LLMError.t()}
  def generate(%Agent{} = conversation, opts \\ []) when is_list(opts) do
    with {:ok, execution} <- resolve_execution(conversation, opts),
         {:ok, request} <- build_request(conversation, execution, opts),
         {:ok, result, execution_ref} <- execute_backend(execution, request, opts),
         {:ok, assistant_text} <- ensure_assistant_text(result),
         {:ok, record_metadata} <-
           to_map(Keyword.get(opts, :record_metadata, %{}), :record_metadata),
         {:ok, next_conversation} <-
           append_assistant_message(
             conversation,
             assistant_text,
             assistant_metadata(request, result, execution, execution_ref, record_metadata)
           ) do
      {:ok, next_conversation, result}
    end
  end

  defp resolve_execution(%Agent{} = conversation, opts) do
    llm_defaults =
      conversation.state
      |> get_field(:llm)
      |> normalize_map()

    with {:ok, llm_overrides} <- to_map(Keyword.get(opts, :llm, %{}), :llm),
         overrides <-
           llm_overrides
           |> put_present(:backend, Keyword.get(opts, :backend))
           |> put_present(:provider, Keyword.get(opts, :provider))
           |> put_present(:model, Keyword.get(opts, :model))
           |> put_present(:stream?, normalize_boolean(Keyword.get(opts, :stream?)))
           |> put_present(:timeout_ms, optional_positive_int(Keyword.get(opts, :timeout_ms))),
         llm_config <- Keyword.get(opts, :llm_config, Config.llm()),
         {:ok, execution} <- LLMResolver.resolve(overrides, llm_defaults, llm_config) do
      {:ok, execution}
    else
      {:error, %LLMError{} = error} -> {:error, error}
    end
  end

  defp build_request(%Agent{} = conversation, execution, opts) do
    with {:ok, request_options} <-
           to_map(Keyword.get(opts, :request_options, %{}), :request_options),
         {:ok, request_metadata} <- to_map(Keyword.get(opts, :metadata, %{}), :metadata) do
      context_options = [
        max_messages: Keyword.get(opts, :max_messages, 40),
        include_system: Keyword.get(opts, :include_system, false),
        include_tool: Keyword.get(opts, :include_tool, false)
      ]

      request_attrs = %{
        request_id: Keyword.get(opts, :request_id, "llm-" <> Jido.Util.generate_id()),
        conversation_id: conversation_id(conversation),
        backend: execution.backend,
        messages: llm_messages(conversation, context_options),
        model: execution.model,
        provider: execution.provider,
        system_prompt: normalize_optional_binary(Keyword.get(opts, :system_prompt)),
        stream?: request_stream?(execution, opts),
        max_tokens: optional_positive_int(Keyword.get(opts, :max_tokens)),
        temperature: optional_number(Keyword.get(opts, :temperature)),
        timeout_ms:
          first_non_nil([
            optional_positive_int(Keyword.get(opts, :timeout_ms)),
            execution.timeout_ms
          ]),
        metadata: request_metadata,
        options: request_options
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
  end

  defp execute_backend(execution, %LLMRequest{} = request, opts) do
    module = Map.get(execution, :module)

    with :ok <- ensure_backend_function(module, request.stream?),
         {:ok, backend_overrides} <-
           normalize_backend_overrides(Keyword.get(opts, :backend_opts, [])),
         backend_opts <-
           Keyword.merge(backend_options(Map.get(execution, :options, %{})), backend_overrides),
         {:ok, response} <-
           run_backend(module, request, backend_opts, Keyword.get(opts, :on_event)) do
      normalize_backend_response(response)
    end
  end

  defp ensure_backend_function(module, stream?) when is_atom(module) do
    function = if stream?, do: :stream, else: :start
    arity = if stream?, do: 3, else: 2

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

  defp ensure_backend_function(module, _stream?) do
    {:error,
     LLMError.new!(
       category: :config,
       message: "invalid llm backend module",
       details: %{module: module}
     )}
  end

  defp run_backend(module, %LLMRequest{stream?: true} = request, backend_opts, on_event) do
    emit = fn event ->
      maybe_emit_event(on_event, event)
      :ok
    end

    invoke_backend(module, :stream, [request, emit, backend_opts])
  end

  defp run_backend(module, %LLMRequest{} = request, backend_opts, _on_event) do
    invoke_backend(module, :start, [request, backend_opts])
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
    {:error, non_completed_result_error(result)}
  end

  defp normalize_backend_response({:ok, %LLMResult{} = result, _execution_ref}) do
    {:error, non_completed_result_error(result)}
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

  defp non_completed_result_error(%LLMResult{status: :failed} = result) do
    result.error ||
      LLMError.new!(
        category: :provider,
        message: "llm backend returned a failed result",
        details: %{result: Map.from_struct(result)}
      )
  end

  defp non_completed_result_error(%LLMResult{status: :canceled} = result) do
    result.error ||
      LLMError.new!(
        category: :canceled,
        message: "llm backend returned a canceled result",
        details: %{result: Map.from_struct(result)}
      )
  end

  defp non_completed_result_error(%LLMResult{} = result) do
    LLMError.new!(
      category: :unknown,
      message: "llm backend returned an unsupported result status",
      details: %{status: result.status}
    )
  end

  defp ensure_assistant_text(%LLMResult{text: text}) when is_binary(text) do
    case String.trim(text) do
      "" ->
        {:error,
         LLMError.new!(
           category: :provider,
           message: "llm backend returned empty assistant text",
           retryable?: false
         )}

      _ ->
        {:ok, text}
    end
  end

  defp ensure_assistant_text(_result) do
    {:error,
     LLMError.new!(
       category: :provider,
       message: "llm backend returned an invalid assistant text payload",
       retryable?: false
     )}
  end

  defp append_assistant_message(%Agent{} = conversation, assistant_text, metadata) do
    case Conversation.record_assistant_message(conversation, assistant_text, metadata: metadata) do
      {:ok, next_conversation, _directives} ->
        {:ok, next_conversation}

      {:error, reason} ->
        {:error,
         LLMError.from_reason(reason, :unknown, message: "failed to record assistant message")}
    end
  end

  defp assistant_metadata(request, result, execution, execution_ref, record_metadata) do
    %{
      request_id: request.request_id,
      backend: normalize_identifier(first_non_nil([result.backend, execution.backend])),
      provider: normalize_identifier(first_non_nil([result.provider, execution.provider])),
      model: normalize_identifier(first_non_nil([result.model, execution.model])),
      finish_reason: normalize_identifier(result.finish_reason),
      usage: normalize_map(result.usage),
      llm_metadata: normalize_map(result.metadata)
    }
    |> maybe_put(:execution_ref, if(is_nil(execution_ref), do: nil, else: inspect(execution_ref)))
    |> compact_map()
    |> Map.merge(record_metadata)
  end

  defp normalize_backend_overrides(nil), do: {:ok, []}
  defp normalize_backend_overrides(overrides) when is_list(overrides), do: {:ok, overrides}

  defp normalize_backend_overrides(overrides) when is_map(overrides) do
    {:ok, backend_options(overrides)}
  end

  defp normalize_backend_overrides(other) do
    {:error,
     LLMError.new!(
       category: :config,
       message: "invalid llm backend options overrides",
       details: %{value: other}
     )}
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

  defp backend_options(_), do: []

  defp existing_atom_key(key) when is_binary(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> nil
  end

  defp maybe_emit_event(callback, event) when is_function(callback, 1) do
    _ = callback.(event)
    :ok
  rescue
    _ -> :ok
  catch
    _, _ -> :ok
  end

  defp maybe_emit_event(_callback, _event), do: :ok

  defp llm_messages(%Agent{} = conversation, context_options) do
    conversation
    |> Conversation.llm_context(context_options)
    |> Enum.map(fn message ->
      %{
        role: message.role,
        content: message.content
      }
    end)
  end

  defp request_stream?(execution, opts) do
    case normalize_boolean(Keyword.get(opts, :stream?)) do
      nil -> Map.get(execution, :stream?, true)
      value -> value
    end
  end

  defp conversation_id(%Agent{} = conversation) do
    first_non_nil([get_field(conversation.state, :conversation_id), conversation.id])
  end

  defp to_map(nil, _source), do: {:ok, %{}}
  defp to_map(value, _source) when is_map(value), do: {:ok, value}

  defp to_map(value, _source) when is_list(value) do
    if Keyword.keyword?(value) do
      {:ok, Map.new(value)}
    else
      {:error,
       LLMError.new!(
         category: :config,
         message: "invalid llm option map",
         details: %{value: value}
       )}
    end
  end

  defp to_map(other, source) do
    {:error,
     LLMError.new!(
       category: :config,
       message: "invalid #{source} payload",
       details: %{value: other}
     )}
  end

  defp normalize_map(value) when is_map(value), do: value
  defp normalize_map(_), do: %{}

  defp get_field(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, to_string(key))
  end

  defp get_field(_map, _key), do: nil

  defp put_present(map, _key, nil), do: map
  defp put_present(map, key, value), do: Map.put(map, key, value)

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp first_non_nil(values) when is_list(values), do: Enum.find(values, &(not is_nil(&1)))

  defp normalize_boolean(value) when is_boolean(value), do: value
  defp normalize_boolean(_), do: nil

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

  defp normalize_optional_binary(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_optional_binary(_), do: nil

  defp normalize_identifier(nil), do: nil
  defp normalize_identifier(value) when is_atom(value), do: Atom.to_string(value)

  defp normalize_identifier(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_identifier(value), do: inspect(value)

  defp compact_map(map) when is_map(map) do
    Enum.reduce(map, %{}, fn
      {_key, nil}, acc -> acc
      {key, value}, acc -> Map.put(acc, key, value)
    end)
  end
end
