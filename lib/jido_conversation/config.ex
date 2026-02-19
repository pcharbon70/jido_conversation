defmodule JidoConversation.Config do
  @moduledoc """
  Accessors and validation for event-system runtime configuration.
  """

  alias Jido.Signal.Journal.Adapters.ETS
  alias JidoConversation.Signal.Router

  @app :jido_conversation
  @key JidoConversation.EventSystem

  @default_config [
    bus_name: :jido_conversation_bus,
    journal_adapter: ETS,
    journal_adapter_opts: [],
    ingestion_dedupe_cache_size: 50_000,
    partition_count: 4,
    max_log_size: 100_000,
    log_ttl_ms: nil,
    runtime_partitions: 4,
    subscription_pattern: "conv.**",
    persistent_subscription: [
      max_in_flight: 100,
      max_pending: 5_000,
      max_attempts: 5,
      retry_interval: 500
    ],
    effect_runtime: [
      llm: [max_attempts: 3, backoff_ms: 100, timeout_ms: 5_000],
      tool: [max_attempts: 3, backoff_ms: 100, timeout_ms: 3_000],
      timer: [max_attempts: 2, backoff_ms: 50, timeout_ms: 1_000]
    ]
  ]

  @telemetry_events [
    [:jido, :signal, :bus, :before_dispatch],
    [:jido, :signal, :bus, :after_dispatch],
    [:jido, :signal, :bus, :dispatch_error],
    [:jido, :signal, :subscription, :dispatch, :retry],
    [:jido, :signal, :subscription, :dlq],
    [:jido, :signal, :bus, :subscription_backpressure],
    [:jido, :signal, :bus, :backpressure],
    [:jido, :signal, :bus, :log_prune],
    [:jido, :dispatch, :exception],
    [:jido_conversation, :runtime, :queue, :depth],
    [:jido_conversation, :runtime, :apply, :stop],
    [:jido_conversation, :runtime, :abort, :latency]
  ]

  @type t :: keyword()

  @spec event_system() :: t()
  def event_system do
    configured = Application.get_env(@app, @key, [])

    Keyword.merge(@default_config, configured, fn
      :persistent_subscription, defaults, overrides when is_list(overrides) ->
        Keyword.merge(defaults, overrides)

      :effect_runtime, defaults, overrides when is_list(overrides) ->
        Keyword.merge(defaults, overrides, fn
          _class, class_defaults, class_overrides when is_list(class_overrides) ->
            Keyword.merge(class_defaults, class_overrides)

          _class, _class_defaults, class_overrides ->
            class_overrides
        end)

      _key, _defaults, overrides ->
        overrides
    end)
  end

  @spec validate!() :: :ok
  def validate! do
    cfg = event_system()

    ensure_atom!(cfg[:bus_name], :bus_name)
    ensure_atom!(cfg[:journal_adapter], :journal_adapter)
    ensure_positive_integer!(cfg[:ingestion_dedupe_cache_size], :ingestion_dedupe_cache_size)
    ensure_positive_integer!(cfg[:partition_count], :partition_count)
    ensure_positive_integer!(cfg[:runtime_partitions], :runtime_partitions)
    ensure_binary!(cfg[:subscription_pattern], :subscription_pattern)
    validate_effect_runtime!(cfg[:effect_runtime])

    :ok
  end

  @spec bus_name() :: atom()
  def bus_name do
    event_system() |> Keyword.fetch!(:bus_name)
  end

  @spec runtime_partitions() :: pos_integer()
  def runtime_partitions do
    event_system() |> Keyword.fetch!(:runtime_partitions)
  end

  @spec journal_adapter() :: module()
  def journal_adapter do
    event_system() |> Keyword.fetch!(:journal_adapter)
  end

  @spec ingestion_dedupe_cache_size() :: pos_integer()
  def ingestion_dedupe_cache_size do
    event_system() |> Keyword.fetch!(:ingestion_dedupe_cache_size)
  end

  @spec subscription_pattern() :: String.t()
  def subscription_pattern do
    event_system() |> Keyword.fetch!(:subscription_pattern)
  end

  @spec effect_runtime_policy(:llm | :tool | :timer) :: keyword()
  def effect_runtime_policy(class) when class in [:llm, :tool, :timer] do
    event_system()
    |> Keyword.fetch!(:effect_runtime)
    |> Keyword.fetch!(class)
  end

  def telemetry_events, do: @telemetry_events

  @spec bus_options() :: keyword()
  def bus_options do
    cfg = event_system()

    [
      name: cfg[:bus_name],
      router: Router.new!(),
      journal_adapter: cfg[:journal_adapter],
      journal_adapter_opts: cfg[:journal_adapter_opts],
      partition_count: cfg[:partition_count],
      max_log_size: cfg[:max_log_size],
      log_ttl_ms: cfg[:log_ttl_ms]
    ]
  end

  @spec persistent_subscription_options(pid()) :: keyword()
  def persistent_subscription_options(target_pid) when is_pid(target_pid) do
    cfg = event_system()

    [dispatch: {:pid, target: target_pid}, persistent?: true] ++
      Keyword.fetch!(cfg, :persistent_subscription)
  end

  defp ensure_atom!(value, _key) when is_atom(value), do: :ok

  defp ensure_atom!(value, key) do
    raise ArgumentError, "expected #{key} to be an atom, got: #{inspect(value)}"
  end

  defp ensure_binary!(value, _key) when is_binary(value), do: :ok

  defp ensure_binary!(value, key) do
    raise ArgumentError, "expected #{key} to be a binary, got: #{inspect(value)}"
  end

  defp ensure_positive_integer!(value, _key) when is_integer(value) and value > 0, do: :ok

  defp ensure_positive_integer!(value, key) do
    raise ArgumentError,
          "expected #{key} to be a positive integer, got: #{inspect(value)}"
  end

  defp validate_effect_runtime!(policies) when is_list(policies) do
    Enum.each([:llm, :tool, :timer], fn class ->
      class_policy = Keyword.fetch!(policies, class)

      ensure_positive_integer!(
        Keyword.fetch!(class_policy, :max_attempts),
        :"effect_runtime.#{class}.max_attempts"
      )

      ensure_positive_integer!(
        Keyword.fetch!(class_policy, :backoff_ms),
        :"effect_runtime.#{class}.backoff_ms"
      )

      ensure_positive_integer!(
        Keyword.fetch!(class_policy, :timeout_ms),
        :"effect_runtime.#{class}.timeout_ms"
      )
    end)

    :ok
  end

  defp validate_effect_runtime!(other) do
    raise ArgumentError, "expected effect_runtime to be a keyword list, got: #{inspect(other)}"
  end
end
