defmodule Jido.Conversation.Mode.Registry do
  @moduledoc """
  Mode registry and deterministic discovery for built-in and configured modes.

  Source precedence:
  1. built-in defaults
  2. application config (`:jido_conversation, :mode_registry`)
  3. runtime overrides (`:runtime_overrides` option)

  Duplicate policy:
  - Duplicate IDs inside the same source are rejected.
  - Higher-precedence sources replace lower-precedence definitions.
  """

  alias Jido.Conversation.Mode
  alias Jido.Conversation.Mode.Coding
  alias Jido.Conversation.Mode.Engineering
  alias Jido.Conversation.Mode.Planning

  @type mode_id :: atom()
  @type mode_module :: module()
  @type unknown_keys_policy :: :allow | :reject
  @type stability :: :stable | :experimental
  @type source :: :built_in | :app_config | :runtime_override

  @type mode_metadata :: %{
          required(:id) => mode_id(),
          required(:module) => mode_module(),
          required(:source) => source(),
          required(:summary) => String.t(),
          required(:capabilities) => map(),
          required(:required_options) => [atom()],
          required(:optional_options) => [atom()],
          required(:defaults) => map(),
          required(:unknown_keys_policy) => unknown_keys_policy(),
          required(:stability) => stability(),
          required(:version) => pos_integer()
        }

  @type registry :: %{mode_id() => mode_metadata()}
  @type source_entry :: mode_module() | {mode_id(), mode_module()} | mode_id()

  @built_in_modes [Coding, Planning, Engineering]
  @metadata_callbacks [
    {:summary, 0},
    {:capabilities, 0},
    {:required_options, 0},
    {:optional_options, 0},
    {:defaults, 0},
    {:unknown_keys_policy, 0},
    {:stability, 0},
    {:version, 0}
  ]

  @spec supported_modes(keyword()) :: [mode_id()]
  def supported_modes(opts \\ []) when is_list(opts) do
    opts
    |> supported_mode_metadata()
    |> Enum.map(& &1.id)
  end

  @spec supported_mode_metadata(keyword()) :: [mode_metadata()]
  def supported_mode_metadata(opts \\ []) when is_list(opts) do
    opts
    |> resolve()
    |> case do
      {:ok, registry} -> ordered(registry, opts)
      {:error, _reason} -> built_in_metadata(opts)
    end
  end

  @spec fetch(mode_id(), keyword()) ::
          {:ok, mode_metadata()} | {:error, {:unsupported_mode, mode_id(), [mode_id()]} | term()}
  def fetch(mode_id, opts \\ []) when is_atom(mode_id) and is_list(opts) do
    with {:ok, registry} <- resolve(opts) do
      case Map.fetch(registry, mode_id) do
        {:ok, metadata} ->
          {:ok, metadata}

        :error ->
          {:error, {:unsupported_mode, mode_id, ordered_mode_ids(registry)}}
      end
    end
  end

  @spec resolve(keyword()) :: {:ok, registry()} | {:error, term()}
  def resolve(opts \\ []) when is_list(opts) do
    with {:ok, built_in_registry} <- normalize_source(@built_in_modes, :built_in),
         {:ok, app_registry} <- normalize_source(app_config_entries(), :app_config),
         {:ok, runtime_registry} <-
           normalize_source(Keyword.get(opts, :runtime_overrides, []), :runtime_override) do
      {:ok, merge_sources([built_in_registry, app_registry, runtime_registry])}
    end
  end

  defp app_config_entries do
    case Application.get_env(:jido_conversation, :mode_registry, []) do
      entries when is_list(entries) -> entries
      entries when is_map(entries) -> Map.to_list(entries)
      _other -> []
    end
  end

  defp built_in_metadata(opts) do
    case normalize_source(@built_in_modes, :built_in) do
      {:ok, registry} -> ordered(registry, opts)
      {:error, _reason} -> []
    end
  end

  defp merge_sources(registries) do
    Enum.reduce(registries, %{}, fn registry, acc -> Map.merge(acc, registry) end)
  end

  defp normalize_source(entries, source)
       when is_list(entries) and source in [:built_in, :app_config, :runtime_override] do
    entries
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, %{}}, fn {entry, index}, {:ok, acc} ->
      with {:ok, module, expected_id} <- resolve_entry(entry),
           {:ok, metadata} <- metadata_from_module(module, source),
           :ok <- validate_expected_id(expected_id, metadata.id),
           :ok <- ensure_unique_id(acc, metadata.id, source) do
        metadata = Map.put(metadata, :order, {source_rank(source), index, metadata.id})
        {:cont, {:ok, Map.put(acc, metadata.id, metadata)}}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp normalize_source(_entries, source)
       when source in [:built_in, :app_config, :runtime_override],
       do: {:ok, %{}}

  defp source_rank(:built_in), do: 0
  defp source_rank(:app_config), do: 1
  defp source_rank(:runtime_override), do: 2

  defp ordered(registry, opts) do
    stability_filter = Keyword.get(opts, :stability, :all)

    registry
    |> Map.values()
    |> Enum.filter(&stability_match?(&1.stability, stability_filter))
    |> Enum.sort_by(& &1.order)
    |> Enum.map(&Map.delete(&1, :order))
  end

  defp ordered_mode_ids(registry) do
    registry
    |> ordered()
    |> Enum.map(& &1.id)
  end

  defp ordered(registry) do
    registry
    |> Map.values()
    |> Enum.sort_by(& &1.order)
  end

  defp stability_match?(_stability, :all), do: true
  defp stability_match?(stability, filter), do: stability == filter

  defp ensure_unique_id(acc, mode_id, source) do
    if Map.has_key?(acc, mode_id) do
      {:error, {:duplicate_mode_id, source, mode_id}}
    else
      :ok
    end
  end

  defp validate_expected_id(nil, _actual_id), do: :ok
  defp validate_expected_id(expected_id, expected_id), do: :ok

  defp validate_expected_id(expected_id, actual_id),
    do: {:error, {:mode_id_mismatch, expected_id, actual_id}}

  defp resolve_entry({mode_id, module}) when is_atom(mode_id) and is_atom(module) do
    {:ok, module, mode_id}
  end

  defp resolve_entry(module) when is_atom(module) do
    if mode_module?(module) do
      {:ok, module, nil}
    else
      resolve_mode_id_entry(module)
    end
  end

  defp resolve_entry(entry), do: {:error, {:invalid_registry_entry, entry}}

  defp resolve_mode_id_entry(mode_id) when is_atom(mode_id) do
    case Enum.find(@built_in_modes, fn module -> module.id() == mode_id end) do
      nil -> {:error, {:unknown_mode_id, mode_id}}
      module -> {:ok, module, mode_id}
    end
  end

  defp mode_module?(module) when is_atom(module) do
    with {:module, _loaded} <- Code.ensure_loaded(module),
         true <- function_exported?(module, :id, 0),
         mode_id when is_atom(mode_id) <- module.id() do
      mode_id != nil
    else
      _ -> false
    end
  end

  defp metadata_from_module(module, source) do
    with {:module, _loaded} <- Code.ensure_loaded(module),
         :ok <- validate_callbacks(module),
         mode_id when is_atom(mode_id) <- module.id(),
         {:ok, capabilities} <- normalize_capabilities(module.capabilities()),
         {:ok, required_options} <- normalize_option_list(module.required_options()),
         {:ok, optional_options} <- normalize_option_list(module.optional_options()),
         {:ok, defaults} <- normalize_defaults(module.defaults()),
         {:ok, unknown_keys_policy} <- normalize_unknown_policy(module.unknown_keys_policy()),
         {:ok, stability} <- normalize_stability(module.stability()),
         {:ok, version} <- normalize_version(module.version()) do
      {:ok,
       %{
         id: mode_id,
         module: module,
         source: source,
         summary: normalize_summary(module.summary()),
         capabilities: capabilities,
         required_options: required_options,
         optional_options: optional_options,
         defaults: defaults,
         unknown_keys_policy: unknown_keys_policy,
         stability: stability,
         version: version
       }}
    else
      {:error, reason} ->
        {:error, reason}

      false ->
        {:error, {:invalid_mode_id, module.id()}}

      {:error, _reason, _stacktrace} ->
        {:error, {:invalid_mode_module, module}}

      _other ->
        {:error, {:invalid_mode_module, module}}
    end
  rescue
    _error ->
      {:error, {:invalid_mode_module, module}}
  end

  defp validate_callbacks(module) do
    required_callbacks = Mode.behaviour_info(:callbacks)

    missing_callbacks =
      required_callbacks
      |> Enum.reject(fn {name, arity} -> function_exported?(module, name, arity) end)

    missing_metadata =
      @metadata_callbacks
      |> Enum.reject(fn {name, arity} -> function_exported?(module, name, arity) end)

    case {missing_callbacks, missing_metadata} do
      {[], []} ->
        :ok

      {callbacks, metadata} ->
        {:error, {:missing_mode_callbacks, module, callbacks, metadata}}
    end
  end

  defp normalize_summary(summary) when is_binary(summary), do: String.trim(summary)
  defp normalize_summary(_summary), do: ""

  defp normalize_capabilities(value) when is_map(value), do: {:ok, value}
  defp normalize_capabilities(value), do: {:error, {:invalid_capabilities, value}}

  defp normalize_option_list(value) when is_list(value) do
    value
    |> Enum.reduce_while({:ok, []}, fn
      key, {:ok, acc} when is_atom(key) -> {:cont, {:ok, [key | acc]}}
      _key, _acc -> {:halt, {:error, {:invalid_mode_options, value}}}
    end)
    |> case do
      {:ok, list} -> {:ok, list |> Enum.reverse() |> Enum.uniq()}
      error -> error
    end
  end

  defp normalize_option_list(value), do: {:error, {:invalid_mode_options, value}}

  defp normalize_defaults(value) when is_map(value), do: {:ok, value}
  defp normalize_defaults(value), do: {:error, {:invalid_defaults, value}}

  defp normalize_unknown_policy(:allow), do: {:ok, :allow}
  defp normalize_unknown_policy(:reject), do: {:ok, :reject}
  defp normalize_unknown_policy(value), do: {:error, {:invalid_unknown_keys_policy, value}}

  defp normalize_stability(:stable), do: {:ok, :stable}
  defp normalize_stability(:experimental), do: {:ok, :experimental}
  defp normalize_stability(value), do: {:error, {:invalid_stability, value}}

  defp normalize_version(version) when is_integer(version) and version > 0, do: {:ok, version}
  defp normalize_version(version), do: {:error, {:invalid_version, version}}
end
