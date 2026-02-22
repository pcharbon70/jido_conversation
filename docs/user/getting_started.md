# Getting Started

## 1. Add dependency

Use whichever source your host application uses (path/git/registry). Example
for local integration:

```elixir
defp deps do
  [
    {:jido_conversation, path: "../jido_conversation"}
  ]
end
```

## 2. Configure the event system

Add host config (adjust values by environment):

```elixir
import Config

config :jido_conversation, Jido.Conversation.EventSystem,
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
  ]
```

## 3. Ingest your first event

```elixir
conversation_id = "conv-123"

{:ok, _result} =
  Jido.Conversation.ingest(%{
    type: "conv.in.message.received",
    source: "/messaging/web",
    subject: conversation_id,
    data: %{
      message_id: "msg-1",
      ingress: "web",
      text: "Hello!"
    },
    extensions: %{
      contract_major: 1
    }
  })
```

## 4. Read projections

```elixir
timeline = Jido.Conversation.timeline(conversation_id)
llm_context = Jido.Conversation.llm_context(conversation_id)
```

## 5. Add runtime diagnostics

```elixir
health = Jido.Conversation.health()
metrics = Jido.Conversation.telemetry_snapshot()
```

## Next guides

- LLM backend and override configuration: `docs/user/llm_backend_configuration.md`
- Event ingestion patterns: `docs/user/ingesting_events.md`
- Projection and replay usage: `docs/user/projections_and_replay.md`
- Host operations integration: `docs/user/operations_and_host_integration.md`
