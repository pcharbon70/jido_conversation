defmodule Jido.Conversation.LLM.Result do
  @moduledoc """
  Normalized final response from an LLM backend adapter.
  """

  alias Jido.Conversation.LLM.Error

  @statuses [:completed, :failed, :canceled]

  @type backend :: :jido_ai | :harness | atom()
  @type status :: :completed | :failed | :canceled

  @type t :: %__MODULE__{
          request_id: String.t(),
          conversation_id: String.t(),
          backend: backend(),
          status: status(),
          text: String.t() | nil,
          model: String.t() | atom() | nil,
          provider: String.t() | atom() | nil,
          finish_reason: String.t() | atom() | nil,
          usage: map(),
          metadata: map(),
          error: Error.t() | nil
        }

  @type validation_error ::
          {:field,
           :request_id
           | :conversation_id
           | :backend
           | :status
           | :text
           | :model
           | :provider
           | :finish_reason
           | :usage
           | :metadata, :missing | :invalid}
          | {:status, :unsupported, [status()]}
          | {:status, :error_required}
          | {:status, :error_forbidden}
          | {:error, :invalid}

  defstruct request_id: nil,
            conversation_id: nil,
            backend: nil,
            status: nil,
            text: nil,
            model: nil,
            provider: nil,
            finish_reason: nil,
            usage: %{},
            metadata: %{},
            error: nil

  @spec statuses() :: [status(), ...]
  def statuses, do: @statuses

  @spec new(map() | keyword()) :: {:ok, t()} | {:error, validation_error() | term()}
  def new(attrs) when is_list(attrs) do
    attrs
    |> Enum.into(%{})
    |> new()
  end

  def new(attrs) when is_map(attrs) do
    result = %__MODULE__{
      request_id: get_field(attrs, :request_id),
      conversation_id: get_field(attrs, :conversation_id),
      backend: get_field(attrs, :backend),
      status: get_field(attrs, :status),
      text: normalize_optional_binary(get_field(attrs, :text)),
      model: normalize_atom_or_binary(get_field(attrs, :model)),
      provider: normalize_atom_or_binary(get_field(attrs, :provider)),
      finish_reason: normalize_atom_or_binary(get_field(attrs, :finish_reason)),
      usage: normalize_map(get_field(attrs, :usage)),
      metadata: normalize_map(get_field(attrs, :metadata)),
      error: get_field(attrs, :error)
    }

    with :ok <- validate_required_binary(result.request_id, :request_id),
         :ok <- validate_required_binary(result.conversation_id, :conversation_id),
         :ok <- validate_backend(result.backend),
         :ok <- validate_status(result.status),
         :ok <- validate_optional_binary(result.text, :text),
         :ok <- validate_model(result.model),
         :ok <- validate_provider(result.provider),
         :ok <- validate_finish_reason(result.finish_reason),
         :ok <- validate_map(result.usage, :usage),
         :ok <- validate_map(result.metadata, :metadata),
         {:ok, error} <- normalize_error(result.error),
         :ok <- validate_status_error(result.status, error) do
      {:ok, %{result | error: error}}
    end
  end

  def new(other), do: {:error, {:invalid_result, other}}

  @spec new!(map() | keyword()) :: t() | no_return()
  def new!(attrs) do
    case new(attrs) do
      {:ok, result} ->
        result

      {:error, reason} ->
        raise ArgumentError, "invalid llm result: #{inspect(reason)}"
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

  defp validate_backend(nil), do: {:error, {:field, :backend, :missing}}
  defp validate_backend(value) when is_atom(value), do: :ok
  defp validate_backend(_value), do: {:error, {:field, :backend, :invalid}}

  defp validate_status(nil), do: {:error, {:field, :status, :missing}}
  defp validate_status(value) when value in @statuses, do: :ok
  defp validate_status(_value), do: {:error, {:status, :unsupported, @statuses}}

  defp validate_optional_binary(nil, _field), do: :ok
  defp validate_optional_binary(value, _field) when is_binary(value), do: :ok
  defp validate_optional_binary(_value, field), do: {:error, {:field, field, :invalid}}

  defp validate_model(nil), do: :ok
  defp validate_model(value) when is_binary(value) or is_atom(value), do: :ok
  defp validate_model(_value), do: {:error, {:field, :model, :invalid}}

  defp validate_provider(nil), do: :ok
  defp validate_provider(value) when is_binary(value) or is_atom(value), do: :ok
  defp validate_provider(_value), do: {:error, {:field, :provider, :invalid}}

  defp validate_finish_reason(nil), do: :ok
  defp validate_finish_reason(value) when is_binary(value) or is_atom(value), do: :ok
  defp validate_finish_reason(_value), do: {:error, {:field, :finish_reason, :invalid}}

  defp validate_map(value, _field) when is_map(value), do: :ok
  defp validate_map(_value, field), do: {:error, {:field, field, :invalid}}

  defp normalize_error(nil), do: {:ok, nil}
  defp normalize_error(%Error{} = error), do: {:ok, error}

  defp normalize_error(error) when is_map(error) or is_list(error) do
    case Error.new(error) do
      {:ok, normalized} -> {:ok, normalized}
      {:error, _reason} -> {:error, {:error, :invalid}}
    end
  end

  defp normalize_error(_value), do: {:error, {:error, :invalid}}

  defp validate_status_error(:failed, nil), do: {:error, {:status, :error_required}}
  defp validate_status_error(:completed, %Error{}), do: {:error, {:status, :error_forbidden}}
  defp validate_status_error(_status, _error), do: :ok

  defp normalize_optional_binary(nil), do: nil

  defp normalize_optional_binary(value) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: nil, else: value
  end

  defp normalize_optional_binary(value), do: value

  defp normalize_atom_or_binary(value) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: nil, else: value
  end

  defp normalize_atom_or_binary(value), do: value

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
