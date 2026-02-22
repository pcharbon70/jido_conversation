# 07. Projection Layer and Read Models

Projection modules build read views from recorded conversation events.

## Projection facade

- `JidoConversation.Projections.timeline/2`
- `JidoConversation.Projections.llm_context/2`

Both read events through `Ingest.conversation_events/1` and transform to stable
consumer-oriented shapes.

## Timeline projection

`Projections.Timeline` produces entries for:

- user messages (`conv.in.message.received`)
- assistant deltas/completions (`conv.out.assistant.*`)
- tool status (`conv.out.tool.status`)

Key behaviors:

- stable sort by event ID
- optional delta coalescing via `TokenCoalescer`
- metadata passthrough for backend/provider/model/lifecycle context

## LLM context projection

`Projections.LlmContext` maps timeline entries to role/content tuples used for
prompt construction.

Options:

- include assistant deltas or only final assistant messages
- include/exclude tool status entries
- tail truncation by `max_messages`

## Projection design constraints

- Projection code must be side-effect free.
- Views are derived from events only.
- Changes to projection shapes should be backwards-aware for host consumers.
