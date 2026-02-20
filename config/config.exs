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
  effect_runtime: [
    llm: [max_attempts: 3, backoff_ms: 100, timeout_ms: 5_000],
    tool: [max_attempts: 3, backoff_ms: 100, timeout_ms: 3_000],
    timer: [max_attempts: 2, backoff_ms: 50, timeout_ms: 1_000]
  ],
  rollout: [
    mode: :event_based,
    stage: :canary,
    canary: [
      enabled: false,
      subjects: [],
      tenant_ids: [],
      channels: []
    ],
    parity: [
      enabled: false,
      sample_rate: 1.0,
      max_reports: 200,
      legacy_adapter: JidoConversation.Rollout.Parity.NoopLegacyAdapter
    ],
    verification: [
      min_runtime_decisions: 25,
      min_parity_reports: 10,
      max_mismatch_rate: 0.05,
      max_legacy_unavailable_rate: 0.1,
      max_drop_rate: 0.2
    ],
    controller: [
      require_accept_streak: 2,
      rollback_stage: :shadow
    ],
    manager: [
      auto_apply: false,
      max_history: 100
    ],
    window: [
      window_minutes: 60,
      min_assessments: 5,
      required_accept_count: 4,
      max_rollback_count: 0
    ]
  ]

config :jido_signal,
  journal_adapter: Jido.Signal.Journal.Adapters.ETS,
  journal_adapter_opts: []

import_config "#{config_env()}.exs"
