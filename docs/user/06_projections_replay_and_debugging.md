# 06. Projections, Replay, and Debugging

Use projections for product features and replay APIs for diagnostics.

## Timeline projection

```elixir
timeline = JidoConversation.timeline("conv-123")
```

Options:

- `coalesce_deltas` (default `true`)
- `max_delta_chars` (default `280`)

The timeline includes user messages, assistant deltas/completions, and tool
status entries.

## LLM context projection

```elixir
llm_context = JidoConversation.llm_context("conv-123")
```

Options:

- `include_deltas` (default `false`)
- `include_tool_status` (default `true`)
- `max_messages` (default `40`)

Use this projection when preparing prompt history for downstream model calls.

## Replay APIs

```elixir
{:ok, records} = JidoConversation.Ingest.replay("conv.effect.llm.generation.**", 0)
conversation_events = JidoConversation.Ingest.conversation_events("conv-123")
trace = JidoConversation.Ingest.trace_chain("root-signal-id", :forward)
```

## Typical debugging workflow

1. Replay `conv.effect.*` events for the conversation.
2. Confirm lifecycle sequence (`started -> progress -> completed/failed/canceled`).
3. Check projection output for user-visible messages in `conv.out.*`.
4. Inspect telemetry retry counters for category trends.
