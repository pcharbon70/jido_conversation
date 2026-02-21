defmodule JidoConversation.LLM.Event do
  @moduledoc """
  Normalized LLM lifecycle event emitted by backend adapters.
  """

  alias JidoConversation.LLM.Error

  @lifecycles [:started, :delta, :thinking, :completed, :failed, :canceled]

  @type backend :: :jido_ai | :harness | atom()

  @type lifecycle ::
          :started
          | :delta
          | :thinking
          | :completed
          | :failed
          | :canceled

  @type t :: %__MODULE__{
          request_id: String.t(),
          conversation_id: String.t(),
          backend: backend(),
          lifecycle: lifecycle(),
          sequence: non_neg_integer() | nil,
          delta: String.t() | nil,
          content: String.t() | nil,
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
           | :lifecycle
           | :sequence
           | :delta
           | :content
           | :model
           | :provider
           | :finish_reason
           | :usage
           | :metadata, :missing | :invalid}
          | {:lifecycle, :unsupported, [lifecycle()]}
          | {:error, :invalid}

  defstruct request_id: nil,
            conversation_id: nil,
            backend: nil,
            lifecycle: nil,
            sequence: nil,
            delta: nil,
            content: nil,
            model: nil,
            provider: nil,
            finish_reason: nil,
            usage: %{},
            metadata: %{},
            error: nil

  @spec lifecycles() :: [lifecycle(), ...]
  def lifecycles, do: @lifecycles

  @spec new(map() | keyword()) :: {:ok, t()} | {:error, validation_error() | term()}
  def new(attrs) when is_list(attrs) do
    attrs
    |> Enum.into(%{})
    |> new()
  end

  def new(attrs) when is_map(attrs) do
    event = %__MODULE__{
      request_id: get_field(attrs, :request_id),
      conversation_id: get_field(attrs, :conversation_id),
      backend: get_field(attrs, :backend),
      lifecycle: get_field(attrs, :lifecycle),
      sequence: get_field(attrs, :sequence),
      delta: normalize_optional_binary(get_field(attrs, :delta)),
      content: normalize_optional_binary(get_field(attrs, :content)),
      model: normalize_atom_or_binary(get_field(attrs, :model)),
      provider: normalize_atom_or_binary(get_field(attrs, :provider)),
      finish_reason: normalize_atom_or_binary(get_field(attrs, :finish_reason)),
      usage: normalize_map(get_field(attrs, :usage)),
      metadata: normalize_map(get_field(attrs, :metadata)),
      error: get_field(attrs, :error)
    }

    with :ok <- validate_required_binary(event.request_id, :request_id),
         :ok <- validate_required_binary(event.conversation_id, :conversation_id),
         :ok <- validate_backend(event.backend),
         :ok <- validate_lifecycle(event.lifecycle),
         :ok <- validate_optional_non_neg_integer(event.sequence, :sequence),
         :ok <- validate_optional_binary(event.delta, :delta),
         :ok <- validate_optional_binary(event.content, :content),
         :ok <- validate_model(event.model),
         :ok <- validate_provider(event.provider),
         :ok <- validate_finish_reason(event.finish_reason),
         :ok <- validate_map(event.usage, :usage),
         :ok <- validate_map(event.metadata, :metadata),
         {:ok, error} <- normalize_error(event.error) do
      {:ok, %{event | error: error}}
    end
  end

  def new(other), do: {:error, {:invalid_event, other}}

  @spec new!(map() | keyword()) :: t() | no_return()
  def new!(attrs) do
    case new(attrs) do
      {:ok, event} ->
        event

      {:error, reason} ->
        raise ArgumentError, "invalid llm event: #{inspect(reason)}"
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

  defp validate_lifecycle(nil), do: {:error, {:field, :lifecycle, :missing}}
  defp validate_lifecycle(value) when value in @lifecycles, do: :ok
  defp validate_lifecycle(_value), do: {:error, {:lifecycle, :unsupported, @lifecycles}}

  defp validate_optional_non_neg_integer(nil, _field), do: :ok

  defp validate_optional_non_neg_integer(value, _field) when is_integer(value) and value >= 0,
    do: :ok

  defp validate_optional_non_neg_integer(_value, field), do: {:error, {:field, field, :invalid}}

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
