defmodule Jido.Conversation.LLM.Request do
  @moduledoc """
  Normalized LLM request for backend adapters.
  """

  @type backend :: :jido_ai | :harness | atom()

  @type role ::
          :system
          | :user
          | :assistant
          | :tool
          | String.t()
          | atom()

  @type message :: %{
          required(:role) => role(),
          required(:content) => term(),
          optional(atom() | String.t()) => term()
        }

  @type t :: %__MODULE__{
          request_id: String.t(),
          conversation_id: String.t(),
          backend: backend(),
          messages: [message()],
          model: String.t() | atom() | nil,
          provider: String.t() | atom() | nil,
          system_prompt: String.t() | nil,
          stream?: boolean(),
          max_tokens: pos_integer() | nil,
          temperature: number() | nil,
          timeout_ms: pos_integer() | nil,
          metadata: map(),
          options: map()
        }

  @type validation_error ::
          {:field,
           :request_id
           | :conversation_id
           | :backend
           | :messages
           | :model
           | :provider
           | :system_prompt
           | :stream?
           | :max_tokens
           | :temperature
           | :timeout_ms
           | :metadata
           | :options, :missing | :invalid}
          | {:messages, :empty}
          | {:message, non_neg_integer(), :invalid}

  defstruct request_id: nil,
            conversation_id: nil,
            backend: nil,
            messages: [],
            model: nil,
            provider: nil,
            system_prompt: nil,
            stream?: true,
            max_tokens: nil,
            temperature: nil,
            timeout_ms: nil,
            metadata: %{},
            options: %{}

  @spec new(map() | keyword()) :: {:ok, t()} | {:error, validation_error() | term()}
  def new(attrs) when is_list(attrs) do
    attrs
    |> Enum.into(%{})
    |> new()
  end

  def new(attrs) when is_map(attrs) do
    request = %__MODULE__{
      request_id: get_field(attrs, :request_id),
      conversation_id: get_field(attrs, :conversation_id),
      backend: get_field(attrs, :backend),
      messages:
        case get_field(attrs, :messages) do
          nil -> []
          value -> value
        end,
      model: get_field(attrs, :model),
      provider: get_field(attrs, :provider),
      system_prompt: normalize_system_prompt(get_field(attrs, :system_prompt)),
      stream?: normalize_stream(get_field(attrs, :stream?)),
      max_tokens: get_field(attrs, :max_tokens),
      temperature: get_field(attrs, :temperature),
      timeout_ms: get_field(attrs, :timeout_ms),
      metadata: normalize_map(get_field(attrs, :metadata)),
      options: normalize_map(get_field(attrs, :options))
    }

    with :ok <- validate_required_binary(request.request_id, :request_id),
         :ok <- validate_required_binary(request.conversation_id, :conversation_id),
         :ok <- validate_backend(request.backend),
         :ok <- validate_messages(request.messages),
         :ok <- validate_model(request.model),
         :ok <- validate_provider(request.provider),
         :ok <- validate_system_prompt(request.system_prompt),
         :ok <- validate_stream(request.stream?),
         :ok <- validate_max_tokens(request.max_tokens),
         :ok <- validate_temperature(request.temperature),
         :ok <- validate_timeout_ms(request.timeout_ms),
         :ok <- validate_map(request.metadata, :metadata),
         :ok <- validate_map(request.options, :options) do
      {:ok, request}
    end
  end

  def new(other), do: {:error, {:invalid_request, other}}

  @spec new!(map() | keyword()) :: t() | no_return()
  def new!(attrs) do
    case new(attrs) do
      {:ok, request} ->
        request

      {:error, reason} ->
        raise ArgumentError, "invalid llm request: #{inspect(reason)}"
    end
  end

  defp validate_required_binary(nil, field), do: {:error, {:field, field, :missing}}

  defp validate_required_binary(value, field) when is_binary(value) do
    if String.trim(value) == "" do
      {:error, {:field, field, :invalid}}
    else
      :ok
    end
  end

  defp validate_required_binary(_value, field), do: {:error, {:field, field, :invalid}}

  defp validate_backend(value) when is_atom(value), do: :ok
  defp validate_backend(nil), do: {:error, {:field, :backend, :missing}}
  defp validate_backend(_value), do: {:error, {:field, :backend, :invalid}}

  defp validate_messages([]), do: {:error, {:messages, :empty}}

  defp validate_messages(messages) when is_list(messages) do
    messages
    |> Enum.with_index()
    |> Enum.find_value(:ok, fn {message, index} ->
      if valid_message?(message), do: nil, else: {:error, {:message, index, :invalid}}
    end)
  end

  defp validate_messages(_messages), do: {:error, {:field, :messages, :invalid}}

  defp valid_message?(message) when is_map(message) do
    role = get_field(message, :role)
    content = get_field(message, :content)

    valid_role?(role) and not is_nil(content)
  end

  defp valid_message?(_message), do: false

  defp valid_role?(role) when is_atom(role), do: true

  defp valid_role?(role) when is_binary(role) do
    String.trim(role) != ""
  end

  defp valid_role?(_role), do: false

  defp validate_model(nil), do: :ok
  defp validate_model(value) when is_atom(value) or is_binary(value), do: :ok
  defp validate_model(_value), do: {:error, {:field, :model, :invalid}}

  defp validate_provider(nil), do: :ok
  defp validate_provider(value) when is_atom(value) or is_binary(value), do: :ok
  defp validate_provider(_value), do: {:error, {:field, :provider, :invalid}}

  defp validate_system_prompt(nil), do: :ok

  defp validate_system_prompt(value) when is_binary(value) do
    if String.trim(value) == "" do
      {:error, {:field, :system_prompt, :invalid}}
    else
      :ok
    end
  end

  defp validate_system_prompt(_value), do: {:error, {:field, :system_prompt, :invalid}}

  defp validate_stream(value) when is_boolean(value), do: :ok
  defp validate_stream(_value), do: {:error, {:field, :stream?, :invalid}}

  defp validate_max_tokens(nil), do: :ok

  defp validate_max_tokens(value) when is_integer(value) and value > 0, do: :ok
  defp validate_max_tokens(_value), do: {:error, {:field, :max_tokens, :invalid}}

  defp validate_temperature(nil), do: :ok

  defp validate_temperature(value) when is_number(value), do: :ok
  defp validate_temperature(_value), do: {:error, {:field, :temperature, :invalid}}

  defp validate_timeout_ms(nil), do: :ok

  defp validate_timeout_ms(value) when is_integer(value) and value > 0, do: :ok
  defp validate_timeout_ms(_value), do: {:error, {:field, :timeout_ms, :invalid}}

  defp validate_map(map, _field) when is_map(map), do: :ok
  defp validate_map(_value, field), do: {:error, {:field, field, :invalid}}

  defp normalize_system_prompt(value) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: nil, else: value
  end

  defp normalize_system_prompt(value), do: value

  defp normalize_stream(nil), do: true
  defp normalize_stream(value) when is_boolean(value), do: value
  defp normalize_stream(value), do: value

  defp normalize_map(nil), do: %{}
  defp normalize_map(value) when is_map(value), do: value
  defp normalize_map(value) when is_list(value), do: Enum.into(value, %{})
  defp normalize_map(value), do: value

  defp get_field(map, key) when is_map(map) do
    case Map.fetch(map, key) do
      {:ok, value} -> value
      :error -> Map.get(map, to_string(key))
    end
  end
end
