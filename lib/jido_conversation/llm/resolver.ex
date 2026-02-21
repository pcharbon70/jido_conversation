defmodule JidoConversation.LLM.Resolver do
  @moduledoc """
  Resolves LLM backend execution settings from layered defaults.

  Resolution precedence is deterministic:

  1. effect overrides
  2. conversation defaults
  3. application config (`JidoConversation.Config.llm/0`)
  """

  alias JidoConversation.Config
  alias JidoConversation.LLM.Error

  @override_fields [:backend, :module, :provider, :model, :stream?, :timeout_ms, :options]

  @type source_name :: :effect | :conversation | :config

  @type resolved_settings :: %{
          backend: atom(),
          module: module(),
          provider: String.t() | atom() | nil,
          model: String.t() | atom() | nil,
          stream?: boolean(),
          timeout_ms: pos_integer() | nil,
          options: map(),
          sources: %{
            backend: source_name()
          }
        }

  @type source_input :: map() | keyword() | nil

  @spec resolve(source_input(), source_input(), keyword() | nil) ::
          {:ok, resolved_settings()} | {:error, Error.t()}
  def resolve(effect_overrides \\ %{}, conversation_defaults \\ %{}, llm_config \\ nil) do
    llm_config = llm_config || Config.llm()

    with {:ok, llm_config} <- normalize_llm_config(llm_config),
         {:ok, effect} <- normalize_source(effect_overrides, :effect),
         {:ok, conversation} <- normalize_source(conversation_defaults, :conversation),
         {:ok, {backend_source, backend}} <- resolve_backend(effect, conversation, llm_config),
         {:ok, backend_cfg} <- resolve_backend_config(llm_config, backend),
         {:ok, backend_module} <-
           resolve_backend_module(effect, conversation, backend_cfg, backend),
         {:ok, stream?} <- resolve_stream(effect, conversation, backend_cfg, llm_config),
         {:ok, timeout_ms} <- resolve_timeout_ms(effect, conversation, backend_cfg, llm_config),
         {:ok, provider} <-
           resolve_identifier(:provider, effect, conversation, backend_cfg, llm_config),
         {:ok, model} <- resolve_identifier(:model, effect, conversation, backend_cfg, llm_config),
         {:ok, options} <- resolve_options(effect, conversation, backend_cfg) do
      {:ok,
       %{
         backend: backend,
         module: backend_module,
         provider: provider,
         model: model,
         stream?: stream?,
         timeout_ms: timeout_ms,
         options: options,
         sources: %{
           backend: backend_source
         }
       }}
    end
  end

  defp normalize_llm_config(llm_config) when is_list(llm_config) do
    if Keyword.keyword?(llm_config) do
      {:ok, llm_config}
    else
      config_error("invalid llm config payload", %{value: llm_config})
    end
  end

  defp normalize_llm_config(other) do
    config_error("invalid llm config payload", %{value: other})
  end

  defp normalize_source(source, source_name) do
    with {:ok, source_map} <- to_map(source, source_name),
         {:ok, nested_llm} <- extract_nested_llm(source_map, source_name) do
      source_map
      |> extract_override_fields()
      |> then(&Map.merge(nested_llm, &1))
      |> then(&{:ok, &1})
    end
  end

  defp resolve_backend(effect, conversation, llm_config) do
    case pick_with_source([
           {:effect, get_field(effect, :backend)},
           {:conversation, get_field(conversation, :backend)},
           {:config, Keyword.get(llm_config, :default_backend)}
         ]) do
      nil ->
        config_error("unable to resolve llm backend", %{field: :backend})

      {source, backend} when is_atom(backend) ->
        {:ok, {source, backend}}

      {source, backend} ->
        config_error("invalid llm backend value", %{
          field: :backend,
          source: source,
          value: backend
        })
    end
  end

  defp resolve_backend_config(llm_config, backend) do
    backends = Keyword.get(llm_config, :backends, [])

    if is_list(backends) and Keyword.keyword?(backends) do
      case Keyword.fetch(backends, backend) do
        {:ok, backend_cfg} ->
          validate_backend_config(backend, backend_cfg)

        :error ->
          config_error("no llm backend configuration found", %{backend: backend})
      end
    else
      config_error("invalid llm backend table", %{value: backends})
    end
  end

  defp validate_backend_config(backend, backend_cfg) when is_list(backend_cfg) do
    if Keyword.keyword?(backend_cfg) do
      {:ok, backend_cfg}
    else
      config_error("invalid llm backend configuration", %{
        backend: backend,
        value: backend_cfg
      })
    end
  end

  defp validate_backend_config(backend, backend_cfg) do
    config_error("invalid llm backend configuration", %{
      backend: backend,
      value: backend_cfg
    })
  end

  defp resolve_backend_module(effect, conversation, backend_cfg, backend) do
    candidate =
      first_present([
        get_field(effect, :module),
        get_field(conversation, :module),
        Keyword.get(backend_cfg, :module)
      ])

    cond do
      is_nil(candidate) ->
        config_error("llm backend module is not configured", %{
          backend: backend,
          hint: "set llm.backends.#{backend}.module"
        })

      not is_atom(candidate) ->
        config_error("invalid llm backend module", %{backend: backend, value: candidate})

      Code.ensure_loaded?(candidate) ->
        {:ok, candidate}

      true ->
        config_error("llm backend module is not available", %{
          backend: backend,
          module: candidate
        })
    end
  end

  defp resolve_stream(effect, conversation, backend_cfg, llm_config) do
    candidate =
      first_present([
        get_field(effect, :stream?),
        get_field(conversation, :stream?),
        Keyword.get(backend_cfg, :stream?),
        Keyword.get(llm_config, :default_stream?)
      ])

    case candidate do
      value when is_boolean(value) ->
        {:ok, value}

      other ->
        config_error("invalid llm stream setting", %{field: :stream?, value: other})
    end
  end

  defp resolve_timeout_ms(effect, conversation, backend_cfg, llm_config) do
    candidate =
      first_present([
        get_field(effect, :timeout_ms),
        get_field(conversation, :timeout_ms),
        Keyword.get(backend_cfg, :timeout_ms),
        Keyword.get(llm_config, :default_timeout_ms)
      ])

    cond do
      is_nil(candidate) ->
        {:ok, nil}

      is_integer(candidate) and candidate > 0 ->
        {:ok, candidate}

      true ->
        config_error("invalid llm timeout setting", %{field: :timeout_ms, value: candidate})
    end
  end

  defp resolve_identifier(field, effect, conversation, backend_cfg, llm_config) do
    candidate =
      first_present([
        get_field(effect, field),
        get_field(conversation, field),
        Keyword.get(backend_cfg, field),
        Keyword.get(llm_config, default_field(field))
      ])

    cond do
      is_nil(candidate) ->
        {:ok, nil}

      is_atom(candidate) ->
        {:ok, candidate}

      is_binary(candidate) and String.trim(candidate) != "" ->
        {:ok, String.trim(candidate)}

      true ->
        config_error("invalid llm #{field} setting", %{field: field, value: candidate})
    end
  end

  defp resolve_options(effect, conversation, backend_cfg) do
    with {:ok, app_opts} <- options_to_map(Keyword.get(backend_cfg, :options), :config_backend),
         {:ok, conversation_opts} <-
           options_to_map(get_field(conversation, :options), :conversation),
         {:ok, effect_opts} <- options_to_map(get_field(effect, :options), :effect) do
      {:ok, app_opts |> Map.merge(conversation_opts) |> Map.merge(effect_opts)}
    end
  end

  defp options_to_map(nil, _source), do: {:ok, %{}}
  defp options_to_map(map, _source) when is_map(map), do: {:ok, map}

  defp options_to_map(list, source) when is_list(list) do
    if Keyword.keyword?(list) do
      {:ok, Enum.into(list, %{})}
    else
      config_error("invalid llm options payload", %{source: source, value: list})
    end
  end

  defp options_to_map(other, source) do
    config_error("invalid llm options payload", %{source: source, value: other})
  end

  defp extract_nested_llm(source_map, source_name) do
    case fetch_field(source_map, :llm) do
      :error ->
        {:ok, %{}}

      {:ok, nil} ->
        {:ok, %{}}

      {:ok, nested} ->
        to_map(nested, :"#{source_name}.llm")
    end
  end

  defp extract_override_fields(source_map) do
    Enum.reduce(@override_fields, %{}, fn field, acc ->
      case fetch_field(source_map, field) do
        {:ok, value} -> Map.put(acc, field, value)
        :error -> acc
      end
    end)
  end

  defp to_map(nil, _source_name), do: {:ok, %{}}
  defp to_map(map, _source_name) when is_map(map), do: {:ok, map}

  defp to_map(list, source_name) when is_list(list) do
    if Keyword.keyword?(list) do
      {:ok, Enum.into(list, %{})}
    else
      config_error("invalid llm overrides payload", %{source: source_name, value: list})
    end
  end

  defp to_map(other, source_name) do
    config_error("invalid llm overrides payload", %{source: source_name, value: other})
  end

  defp get_field(map, key) when is_map(map) do
    case fetch_field(map, key) do
      {:ok, value} -> value
      :error -> nil
    end
  end

  defp fetch_field(map, key) when is_map(map) do
    case Map.fetch(map, key) do
      {:ok, value} ->
        {:ok, value}

      :error ->
        case Map.fetch(map, to_string(key)) do
          {:ok, value} -> {:ok, value}
          :error -> :error
        end
    end
  end

  defp pick_with_source(pairs) when is_list(pairs) do
    Enum.find(pairs, fn {_source, value} -> not is_nil(value) end)
  end

  defp first_present(values) when is_list(values) do
    Enum.find(values, &(not is_nil(&1)))
  end

  defp default_field(:provider), do: :default_provider
  defp default_field(:model), do: :default_model

  defp config_error(message, details) do
    {:error, Error.new!(category: :config, message: message, details: details, retryable?: false)}
  end
end
