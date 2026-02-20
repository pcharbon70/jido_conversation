import Config

config :jido_conversation, JidoConversation.EventSystem,
  journal_adapter: Jido.Signal.Journal.Adapters.InMemory,
  ingestion_dedupe_cache_size: 100,
  partition_count: 1,
  runtime_partitions: 1,
  persistent_subscription: [
    max_in_flight: 10,
    max_pending: 100,
    max_attempts: 2,
    retry_interval: 10
  ],
  launch_readiness_monitor: [
    enabled: false,
    interval_ms: 500,
    max_queue_depth: 1_000,
    max_dispatch_failures: 0
  ],
  effect_runtime: [
    llm: [max_attempts: 2, backoff_ms: 10, timeout_ms: 60],
    tool: [max_attempts: 2, backoff_ms: 10, timeout_ms: 60],
    timer: [max_attempts: 2, backoff_ms: 10, timeout_ms: 40]
  ]

config :jido_signal,
  journal_adapter: Jido.Signal.Journal.Adapters.InMemory,
  journal_adapter_opts: []
