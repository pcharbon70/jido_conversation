# Projections and Replay

## Projections

### Timeline projection

```elixir
timeline = JidoConversation.timeline("conv-123")
```

Timeline options:

- `coalesce_deltas` (default `true`)
- `max_delta_chars` (default `280`)

```elixir
timeline =
  JidoConversation.timeline("conv-123",
    coalesce_deltas: false,
    max_delta_chars: 120
  )
```

### LLM context projection

```elixir
llm_context = JidoConversation.llm_context("conv-123")
```

LLM context options:

- `include_deltas` (default `false`)
- `include_tool_status` (default `true`)
- `max_messages` (default `40`)

```elixir
llm_context =
  JidoConversation.llm_context("conv-123",
    include_deltas: true,
    include_tool_status: true,
    max_messages: 60
  )
```

## Replay and event queries

Use `JidoConversation.Ingest` for advanced replay/query use cases.

### Per-conversation journal events

```elixir
events = JidoConversation.Ingest.conversation_events("conv-123")
```

This is the best source when you need full event history for a conversation.

### Causal chain tracing

```elixir
upstream_chain = JidoConversation.Ingest.trace_chain("event-id", :backward)
downstream_chain = JidoConversation.Ingest.trace_chain("event-id", :forward)
```

### Stream replay by path + time

```elixir
start_ts = DateTime.utc_now() |> DateTime.to_unix() |> Kernel.-(300)
{:ok, records} = JidoConversation.Ingest.replay("conv.out.**", start_ts)
```

Useful for stream diagnostics and short-window analysis.

## Important replay note

`replay/3` reads from the bus log (bounded by bus log settings like `max_log_size`
and `log_ttl_ms`). For authoritative per-conversation history, use
`conversation_events/1`.
