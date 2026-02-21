defmodule JidoConversation.LLM.Error do
  @moduledoc """
  Normalized backend error representation for LLM runtime operations.
  """

  @categories [:config, :auth, :timeout, :provider, :transport, :canceled, :unknown]

  @default_retryable %{
    config: false,
    auth: false,
    timeout: true,
    provider: true,
    transport: true,
    canceled: false,
    unknown: false
  }

  @type category ::
          :config
          | :auth
          | :timeout
          | :provider
          | :transport
          | :canceled
          | :unknown

  @type t :: %__MODULE__{
          category: category(),
          message: String.t(),
          retryable?: boolean(),
          details: map()
        }

  @type validation_error ::
          {:field, :category | :message | :details | :retryable?, :missing | :invalid}
          | {:category, :unsupported, [category()]}

  defstruct category: :unknown, message: "", retryable?: false, details: %{}

  @spec categories() :: [category(), ...]
  def categories, do: @categories

  @spec new(map() | keyword()) :: {:ok, t()} | {:error, validation_error() | term()}
  def new(attrs) when is_list(attrs) do
    attrs
    |> Enum.into(%{})
    |> new()
  end

  def new(attrs) when is_map(attrs) do
    category = get_field(attrs, :category)
    message = get_field(attrs, :message)

    details =
      case get_field(attrs, :details) do
        nil -> %{}
        value -> value
      end

    retryable? = get_field(attrs, :retryable?)

    with :ok <- validate_category(category),
         :ok <- validate_message(message),
         :ok <- validate_details(details),
         {:ok, normalized_retryable?} <- normalize_retryable(category, retryable?) do
      {:ok,
       %__MODULE__{
         category: category,
         message: String.trim(message),
         retryable?: normalized_retryable?,
         details: details
       }}
    end
  end

  def new(other), do: {:error, {:invalid_error, other}}

  @spec new!(map() | keyword()) :: t() | no_return()
  def new!(attrs) do
    case new(attrs) do
      {:ok, value} ->
        value

      {:error, reason} ->
        raise ArgumentError, "invalid llm error: #{inspect(reason)}"
    end
  end

  @spec from_reason(term(), category(), keyword()) :: t()
  def from_reason(reason, category \\ :unknown, opts \\ [])
      when category in @categories and is_list(opts) do
    message = Keyword.get(opts, :message, normalize_reason(reason))
    details = Keyword.get(opts, :details, %{})
    retryable? = Keyword.get(opts, :retryable?, Map.fetch!(@default_retryable, category))

    new!(%{
      category: category,
      message: message,
      retryable?: retryable?,
      details: Map.put(details, :reason, reason)
    })
  end

  @spec retryable_category?(category()) :: boolean()
  def retryable_category?(category) when category in @categories do
    Map.fetch!(@default_retryable, category)
  end

  defp validate_category(nil), do: {:error, {:field, :category, :missing}}

  defp validate_category(category) when category in @categories, do: :ok

  defp validate_category(_category), do: {:error, {:category, :unsupported, @categories}}

  defp validate_message(nil), do: {:error, {:field, :message, :missing}}

  defp validate_message(message) when is_binary(message) do
    if String.trim(message) == "" do
      {:error, {:field, :message, :invalid}}
    else
      :ok
    end
  end

  defp validate_message(_message), do: {:error, {:field, :message, :invalid}}

  defp validate_details(details) when is_map(details), do: :ok
  defp validate_details(_details), do: {:error, {:field, :details, :invalid}}

  defp normalize_retryable(category, nil), do: {:ok, Map.fetch!(@default_retryable, category)}

  defp normalize_retryable(_category, retryable?) when is_boolean(retryable?) do
    {:ok, retryable?}
  end

  defp normalize_retryable(_category, _value), do: {:error, {:field, :retryable?, :invalid}}

  defp normalize_reason(reason) when is_binary(reason), do: reason

  defp normalize_reason(%{message: message}) when is_binary(message), do: message

  defp normalize_reason(reason), do: inspect(reason)

  defp get_field(map, key) when is_map(map) do
    case Map.fetch(map, key) do
      {:ok, value} -> value
      :error -> Map.get(map, to_string(key))
    end
  end
end
