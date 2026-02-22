# 02. Quickstart

This guide gets a host app running with one conversation message and one
projection query.

## 1. Add dependency

```elixir
defp deps do
  [
    {:jido_conversation, path: "../jido_conversation"}
  ]
end
```

## 2. Configure runtime and LLM backends

```elixir
import Config

config :jido_conversation, Jido.Conversation.EventSystem,
  bus_name: :jido_conversation_bus,
  journal_adapter: Jido.Signal.Journal.Adapters.ETS,
  journal_adapter_opts: [],
  runtime_partitions: 4,
  subscription_pattern: "conv.**",
  effect_runtime: [
    llm: [max_attempts: 3, backoff_ms: 100, timeout_ms: 5_000],
    tool: [max_attempts: 3, backoff_ms: 100, timeout_ms: 3_000],
    timer: [max_attempts: 2, backoff_ms: 50, timeout_ms: 1_000]
  ],
  llm: [
    default_backend: :jido_ai,
    default_stream?: true,
    default_timeout_ms: 30_000,
    backends: [
      jido_ai: [module: Jido.Conversation.LLM.Adapters.JidoAI],
      harness: [module: Jido.Conversation.LLM.Adapters.Harness]
    ]
  ]
```

## 3. Ingest a first message

```elixir
alias Jido.Conversation.Ingest.Adapters.Messaging

conversation_id = "conv-123"

{:ok, _result} =
  Messaging.ingest_received(
    conversation_id,
    "msg-1",
    "web",
    %{text: "Hello from the host app"}
  )
```

## 4. Read projections

```elixir
timeline = Jido.Conversation.timeline(conversation_id)
llm_context = Jido.Conversation.llm_context(conversation_id)
```

## 5. Check runtime diagnostics

```elixir
health = Jido.Conversation.health()
telemetry = Jido.Conversation.telemetry_snapshot()
```

## Next steps

1. Use the ingest adapters in `03_ingest_and_contract.md`.
2. Configure backend/model routing in `05_llm_execution_and_backends.md`.
3. Add replay and debugging workflows from `06_projections_replay_and_debugging.md`.
