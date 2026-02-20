import Config

config :jido_conversation, JidoConversation.EventSystem,
  bus_name: :jido_conversation_bus,
  journal_adapter: Jido.Signal.Journal.Adapters.ETS,
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
  launch_readiness_monitor: [
    enabled: true,
    interval_ms: 60_000,
    max_queue_depth: 1_000,
    max_dispatch_failures: 0
  ],
  effect_runtime: [
    llm: [max_attempts: 3, backoff_ms: 100, timeout_ms: 5_000],
    tool: [max_attempts: 3, backoff_ms: 100, timeout_ms: 3_000],
    timer: [max_attempts: 2, backoff_ms: 50, timeout_ms: 1_000]
  ]

config :jido_signal,
  journal_adapter: Jido.Signal.Journal.Adapters.ETS,
  journal_adapter_opts: []

import_config "#{config_env()}.exs"
