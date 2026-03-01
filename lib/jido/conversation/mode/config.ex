defmodule Jido.Conversation.Mode.Config do
  @moduledoc """
  Resolves effective mode configuration from layered defaults.

  Precedence order:
  1. request options
  2. conversation options
  3. mode defaults
  4. application defaults
  """

  alias Jido.Conversation.Mode.Registry

  @type diagnostic_code :: :required | :unknown_key | :invalid_type | :invalid_key

  @type diagnostic :: %{
          required(:code) => diagnostic_code(),
          required(:path) => [atom() | String.t()],
          required(:message) => String.t()
        }

  @spec resolve(Registry.mode_metadata(), map(), map(), keyword()) ::
          {:ok, map()} | {:error, [diagnostic()]}
  def resolve(mode_metadata, request_options, conversation_options, opts \\ [])
      when is_map(mode_metadata) and is_map(request_options) and is_map(conversation_options) and
             is_list(opts) do
    app_defaults = normalize_map(Keyword.get(opts, :app_defaults, app_defaults(mode_metadata.id)))
    mode_defaults = normalize_map(Map.get(mode_metadata, :defaults, %{}))
    required_options = normalize_option_keys(Map.get(mode_metadata, :required_options, []))
    optional_options = normalize_option_keys(Map.get(mode_metadata, :optional_options, []))
    unknown_keys_policy = Map.get(mode_metadata, :unknown_keys_policy, :allow)
    allowed_options = MapSet.new(required_options ++ optional_options)

    {app_defaults, app_diagnostics} =
      normalize_option_map(
        app_defaults,
        allowed_options,
        mode_defaults,
        [:mode_state, :app_defaults]
      )

    {mode_defaults, mode_diagnostics} =
      normalize_option_map(
        mode_defaults,
        allowed_options,
        mode_defaults,
        [:mode_state, :mode_defaults]
      )

    {conversation_options, conversation_diagnostics} =
      normalize_option_map(
        conversation_options,
        allowed_options,
        mode_defaults,
        [:mode_state, :conversation]
      )

    {request_options, request_diagnostics} =
      normalize_option_map(
        request_options,
        allowed_options,
        mode_defaults,
        [:mode_state, :request]
      )

    merged_options =
      app_defaults
      |> deep_merge(mode_defaults)
      |> deep_merge(conversation_options)
      |> deep_merge(request_options)

    diagnostics =
      app_diagnostics ++
        mode_diagnostics ++
        conversation_diagnostics ++
        request_diagnostics ++
        required_option_diagnostics(merged_options, required_options) ++
        unknown_key_diagnostics(merged_options, allowed_options, unknown_keys_policy)

    if diagnostics == [] do
      {:ok, merged_options}
    else
      {:error, diagnostics}
    end
  end

  defp app_defaults(mode_id) when is_atom(mode_id) do
    case Application.get_env(:jido_conversation, :mode_option_defaults, %{}) do
      defaults when is_map(defaults) ->
        mode_defaults_for(defaults, mode_id)

      _other ->
        %{}
    end
  end

  defp mode_defaults_for(defaults, mode_id) do
    Map.get(defaults, mode_id) ||
      Map.get(defaults, Atom.to_string(mode_id)) ||
      %{}
  end

  defp normalize_option_map(options, allowed_options, defaults, path) do
    Enum.reduce(options, {%{}, []}, fn {key, value}, {acc, diagnostics} ->
      case normalize_key(key, allowed_options) do
        {:ok, normalized_key} ->
          normalized_value = normalize_value(normalized_key, value, defaults)
          {Map.put(acc, normalized_key, normalized_value), diagnostics}

        :error ->
          {
            acc,
            diagnostics ++
              [
                %{
                  code: :invalid_key,
                  path: path ++ [safe_path_key(key)],
                  message: "mode option key must be an atom or string"
                }
              ]
          }
      end
    end)
  end

  defp normalize_key(key, _allowed_options) when is_atom(key), do: {:ok, key}

  defp normalize_key(key, allowed_options) when is_binary(key) do
    trimmed = String.trim(key)

    normalized =
      Enum.find(allowed_options, fn option ->
        Atom.to_string(option) == trimmed
      end)

    if normalized do
      {:ok, normalized}
    else
      {:ok, trimmed}
    end
  end

  defp normalize_key(_key, _allowed_options), do: :error

  defp normalize_value(key, value, defaults) do
    case Map.get(defaults, key) do
      expected when is_integer(expected) -> normalize_integer(value, expected)
      expected when is_boolean(expected) -> normalize_boolean(value, expected)
      _expected -> value
    end
  end

  defp normalize_integer(value, _default) when is_integer(value), do: value

  defp normalize_integer(value, _default) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {parsed, ""} -> parsed
      _other -> value
    end
  end

  defp normalize_integer(value, default), do: value || default

  defp normalize_boolean(value, _default) when is_boolean(value), do: value
  defp normalize_boolean("true", _default), do: true
  defp normalize_boolean("false", _default), do: false
  defp normalize_boolean(value, default), do: value || default

  defp required_option_diagnostics(options, required_options) do
    Enum.flat_map(required_options, fn option ->
      if required_value_present?(Map.get(options, option)) do
        []
      else
        [
          %{
            code: :required,
            path: [:mode_state, option],
            message: "missing required mode option"
          }
        ]
      end
    end)
  end

  defp unknown_key_diagnostics(_options, _allowed_options, :allow), do: []

  defp unknown_key_diagnostics(options, allowed_options, :reject) do
    options
    |> Map.keys()
    |> Enum.flat_map(fn key ->
      if is_atom(key) and MapSet.member?(allowed_options, key) do
        []
      else
        [
          %{
            code: :unknown_key,
            path: [:mode_state, safe_path_key(key)],
            message: "unknown mode option key"
          }
        ]
      end
    end)
  end

  defp unknown_key_diagnostics(_options, _allowed_options, _unknown_policy), do: []

  defp required_value_present?(value) when is_binary(value), do: String.trim(value) != ""
  defp required_value_present?(nil), do: false
  defp required_value_present?(_value), do: true

  defp normalize_map(value) when is_map(value), do: value
  defp normalize_map(_value), do: %{}

  defp normalize_option_keys(value) when is_list(value) do
    value
    |> Enum.filter(&is_atom/1)
    |> Enum.uniq()
  end

  defp normalize_option_keys(_value), do: []

  defp safe_path_key(value) when is_atom(value), do: value
  defp safe_path_key(value) when is_binary(value), do: value
  defp safe_path_key(_value), do: "invalid"

  defp deep_merge(left, right) when is_map(left) and is_map(right) do
    Map.merge(left, right, fn _key, left_value, right_value ->
      if is_map(left_value) and is_map(right_value) do
        deep_merge(left_value, right_value)
      else
        right_value
      end
    end)
  end
end
