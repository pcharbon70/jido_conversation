# Phase 6 messaging integration and projections

## Scope completed

- Extended messaging ingress integration:
  - `JidoConversation.Ingest.Adapters.Messaging.ingest_channel_message/2`
  - Accepts normalized channel payloads (jido_messaging style maps) and emits
    `conv.in.message.received`.
- Added outbound projection adapter:
  - `JidoConversation.Ingest.Adapters.Outbound`
  - Emits contract-compliant `conv.out.*` events with required `output_id` and
    `channel` payload fields.
  - Helper APIs:
    - `emit_assistant_delta/6`
    - `emit_assistant_completed/6`
    - `emit_tool_status/6`
- Added projection layer modules:
  - `JidoConversation.Projections`
  - `JidoConversation.Projections.Timeline`
  - `JidoConversation.Projections.LlmContext`
  - `JidoConversation.Projections.TokenCoalescer`
- Added runtime outbound projection flow:
  - Reducer now emits `:emit_output` directives for effect lifecycle events:
    - `conv.effect.llm.generation.progress` -> `conv.out.assistant.delta`
    - `conv.effect.llm.generation.completed` -> `conv.out.assistant.completed`
    - `conv.effect.tool.execution.*` -> `conv.out.tool.status`
  - Partition worker executes `:emit_output` directives through outbound adapter.
- Added root API convenience methods:
  - `JidoConversation.timeline/2`
  - `JidoConversation.llm_context/2`

## Token delta coalescing policy

- Adjacent assistant delta timeline entries are coalesced when:
  - same `output_id`
  - same `channel`
  - combined content length stays within `max_chars` threshold
- Default threshold: `280` characters.

## Ordering guarantee validation

- Added runtime test ensuring assistant output stream ordering for a conversation:
  - delta event emitted before completed event for the same effect lifecycle.

## Tests added/updated

- Updated:
  - `test/jido_conversation/ingest/adapters_test.exs`
  - `test/jido_conversation/runtime/reducer_test.exs`
  - `test/jido_conversation/runtime/partition_worker_test.exs`
- Added:
  - `test/jido_conversation/projections/timeline_test.exs`
  - `test/jido_conversation/projections/llm_context_test.exs`
  - `test/jido_conversation/projections_test.exs`

## Quality gates

- `mix test`
- `mix credo --strict`
- `mix dialyzer`
