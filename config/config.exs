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
  ]

config :jido_signal,
  journal_adapter: Jido.Signal.Journal.Adapters.ETS,
  journal_adapter_opts: []

import_config "#{config_env()}.exs"
