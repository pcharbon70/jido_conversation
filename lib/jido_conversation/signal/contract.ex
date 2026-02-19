defmodule JidoConversation.Signal.Contract do
  @moduledoc """
  Canonical normalization and validation boundary for conversation signals.

  This module is the phase-2 contract gate at framework boundaries. It ensures
  each signal has required envelope fields, belongs to a supported stream
  namespace, advertises a supported contract major version, and satisfies
  stream-specific payload requirements.
  """

  alias Jido.Signal

  @supported_contract_majors [1]

  @stream_prefixes [
    in: "conv.in.",
    applied: "conv.applied.",
    effect: "conv.effect.",
    out: "conv.out.",
    audit: "conv.audit."
  ]

  @stream_payload_requirements %{
    in: [:message_id, :ingress],
    applied: [:applied_event_id],
    effect: [:effect_id, :lifecycle],
    out: [:output_id, :channel],
    audit: [:audit_id, :category]
  }

  @type stream :: :in | :applied | :effect | :out | :audit

  @type validation_error ::
          {:field, :type | :source | :id | :subject, :missing | :empty | :invalid}
          | {:type_namespace, String.t()}
          | {:contract_version,
             :missing | {:invalid, term()} | {:unsupported, integer(), [integer()]}}
          | {:payload, stream(), {:not_map, term()} | {:missing_keys, [atom()]}}

  @type input :: Signal.t() | map() | keyword()

  @doc """
  Normalizes and validates the given input into a canonical `Jido.Signal`.

  Accepted input forms:
  - `%Jido.Signal{}`
  - map
  - keyword list

  Supported aliases:
  - `conversation_id` -> `subject`
  - top-level `contract_major` -> `extensions.contract_major`
  """
  @spec normalize(input()) :: {:ok, Signal.t()} | {:error, validation_error() | String.t()}
  def normalize(%Signal{} = signal), do: validate(signal)

  def normalize(attrs) when is_list(attrs) do
    attrs |> Enum.into(%{}) |> normalize()
  end

  def normalize(attrs) when is_map(attrs) do
    attrs = normalize_attrs(attrs)

    with {:ok, signal} <- Signal.new(attrs) do
      validate(signal)
    end
  end

  def normalize(_), do: {:error, "expected signal, map, or keyword list"}

  @doc """
  Same as `normalize/1`, but raises `ArgumentError` on failure.
  """
  @spec normalize!(input()) :: Signal.t() | no_return()
  def normalize!(input) do
    case normalize(input) do
      {:ok, signal} -> signal
      {:error, reason} -> raise ArgumentError, "invalid contract signal: #{inspect(reason)}"
    end
  end

  @doc """
  Returns the currently supported contract major versions.
  """
  def supported_contract_majors, do: @supported_contract_majors

  @doc """
  Returns required payload keys for a stream family.
  """
  @spec required_payload_keys(stream()) :: [atom()]
  def required_payload_keys(stream) do
    Map.fetch!(@stream_payload_requirements, stream)
  end

  @doc """
  Validates an already-built signal against the conversation contract.
  """
  @spec validate(Signal.t()) :: {:ok, Signal.t()} | {:error, validation_error()}
  def validate(%Signal{} = signal) do
    with :ok <- validate_required_field(signal.type, :type),
         :ok <- validate_required_field(signal.source, :source),
         :ok <- validate_required_field(signal.id, :id),
         :ok <- validate_required_field(signal.subject, :subject),
         {:ok, stream} <- stream_for_type(signal.type),
         :ok <- validate_contract_version(signal),
         :ok <- validate_payload(stream, signal.data) do
      {:ok, signal}
    end
  end

  defp normalize_attrs(attrs) do
    attrs
    |> stringify_keys()
    |> normalize_subject_alias()
    |> normalize_contract_major_alias()
  end

  defp stringify_keys(attrs) do
    Map.new(attrs, fn {k, v} -> {to_string(k), v} end)
  end

  defp normalize_subject_alias(attrs) do
    {conversation_id, attrs} = Map.pop(attrs, "conversation_id")

    case {Map.get(attrs, "subject"), conversation_id} do
      {nil, subject} when is_binary(subject) and byte_size(subject) > 0 ->
        Map.put(attrs, "subject", subject)

      _ ->
        attrs
    end
  end

  defp normalize_contract_major_alias(attrs) do
    {top_level_major, attrs} = Map.pop(attrs, "contract_major")

    case normalize_extensions(Map.get(attrs, "extensions"), top_level_major) do
      nil -> attrs
      extensions -> Map.put(attrs, "extensions", extensions)
    end
  end

  defp normalize_extensions(nil, nil), do: nil
  defp normalize_extensions(nil, major), do: %{"contract_major" => major}

  defp normalize_extensions(extensions, top_level_major) when is_map(extensions) do
    extensions = stringify_keys(extensions)

    cond do
      Map.has_key?(extensions, "contract_major") ->
        extensions

      is_nil(top_level_major) ->
        extensions

      true ->
        Map.put(extensions, "contract_major", top_level_major)
    end
  end

  defp normalize_extensions(other, _top_level_major), do: other

  defp validate_required_field(nil, field), do: {:error, {:field, field, :missing}}
  defp validate_required_field("", field), do: {:error, {:field, field, :empty}}

  defp validate_required_field(value, field) when is_binary(value) do
    if String.trim(value) == "" do
      {:error, {:field, field, :empty}}
    else
      :ok
    end
  end

  defp validate_required_field(_value, field), do: {:error, {:field, field, :invalid}}

  defp stream_for_type(type) do
    case Enum.find(@stream_prefixes, fn {_stream, prefix} -> String.starts_with?(type, prefix) end) do
      {stream, _prefix} -> {:ok, stream}
      nil -> {:error, {:type_namespace, type}}
    end
  end

  defp validate_contract_version(%Signal{} = signal) do
    major = contract_major(signal)

    cond do
      is_nil(major) ->
        {:error, {:contract_version, :missing}}

      not is_integer(major) or major <= 0 ->
        {:error, {:contract_version, {:invalid, major}}}

      major in @supported_contract_majors ->
        :ok

      true ->
        {:error, {:contract_version, {:unsupported, major, @supported_contract_majors}}}
    end
  end

  defp contract_major(%Signal{} = signal) do
    extensions = signal.extensions || %{}

    Map.get(extensions, "contract_major") ||
      Map.get(extensions, :contract_major)
  end

  defp validate_payload(stream, payload) when not is_map(payload) do
    {:error, {:payload, stream, {:not_map, payload}}}
  end

  defp validate_payload(stream, payload) do
    required_keys = required_payload_keys(stream)

    missing_keys =
      Enum.reject(required_keys, fn key ->
        value_for(payload, key)
        |> present?()
      end)

    case missing_keys do
      [] -> :ok
      _ -> {:error, {:payload, stream, {:missing_keys, missing_keys}}}
    end
  end

  defp value_for(map, key) do
    Map.get(map, key) || Map.get(map, to_string(key))
  end

  defp present?(nil), do: false
  defp present?(""), do: false
  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_), do: true
end
