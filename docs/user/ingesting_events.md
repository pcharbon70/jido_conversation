# Ingesting Events

You can ingest events directly with `JidoConversation.ingest/2` or through
adapter helpers.

## Direct ingest API

```elixir
{:ok, result} =
  JidoConversation.ingest(%{
    type: "conv.effect.tool.execution.started",
    source: "/tool/runtime",
    subject: "conv-123",
    data: %{
      effect_id: "tool-1",
      lifecycle: "started"
    },
    extensions: %{
      contract_major: 1
    }
  })
```

### Notes

- The contract gate validates each event before runtime ingestion.
- Dedupe is keyed by `{subject, id}`; if you reuse the same ID in the same
  conversation, the second ingest is treated as duplicate.
- You can add causality with `cause_id`:

```elixir
JidoConversation.ingest(event_attrs, cause_id: "root-event-id")
```

## Adapter helpers

### Messaging ingress

```elixir
alias JidoConversation.Ingest.Adapters.Messaging

Messaging.ingest_received("conv-123", "msg-1", "web", %{text: "Hello"})
```

### Control ingress (abort)

```elixir
alias JidoConversation.Ingest.Adapters.Control

Control.ingest_abort("conv-123", "ctrl-1", %{reason: "user_cancel"})
```

### Tool lifecycle ingress

```elixir
alias JidoConversation.Ingest.Adapters.Tool

Tool.ingest_lifecycle("conv-123", "tool-1", "progress", %{status: "running"})
Tool.ingest_lifecycle("conv-123", "tool-1", "completed", %{result: %{ok: true}})
```

### LLM lifecycle ingress

```elixir
alias JidoConversation.Ingest.Adapters.Llm

Llm.ingest_lifecycle("conv-123", "llm-1", "progress", %{token_delta: "hi "})
Llm.ingest_lifecycle("conv-123", "llm-1", "completed", %{result: %{text: "hi there"}})
```

### Timer ingress

```elixir
alias JidoConversation.Ingest.Adapters.Timer

Timer.ingest_tick("conv-123", "tick-1", %{kind: "reminder"})
```

### Outbound event helpers

```elixir
alias JidoConversation.Ingest.Adapters.Outbound

Outbound.emit_assistant_delta("conv-123", "out-1", "web", "hello ")
Outbound.emit_assistant_completed("conv-123", "out-1", "web", "hello world")
Outbound.emit_tool_status("conv-123", "tool-out-1", "web", "completed", %{message: "done"})
```

## Backpressure and retries

Under burst load, publish may return `:queue_full` in a `:publish_failed` error.
Host applications should use bounded retry/backoff around ingest calls.
