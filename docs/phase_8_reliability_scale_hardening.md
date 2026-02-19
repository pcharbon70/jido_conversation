# Phase 8 reliability and scale hardening

## Scope completed

- Added reliability-focused operator APIs:
  - `ack_stream/2`
  - `subscription_in_flight/1`
  - `dlq_entries/1`
  - `redrive_dlq/2`
  - `clear_dlq/1`
- Exposed the above through the root `JidoConversation` API.

## Reliability validation coverage

- Added persistent subscription checkpoint recovery test:
  - validates checkpoint advances after explicit ack
  - validates checkpoint survives unsubscribe/re-subscribe with same subscription id
- Added DLQ/re-drive test with transient fault injection:
  - custom dispatch adapter forces initial failures
  - verifies DLQ capture
  - verifies successful re-drive after adapter recovery
- Added high-volume assistant output stress test:
  - emits 40 LLM progress lifecycle events plus completion
  - verifies output stream is fully produced without event loss
  - verifies runtime partition queues drain back to idle

## Files added/updated

- Added:
  - `test/jido_conversation/reliability_test.exs`
  - `docs/phase_8_reliability_scale_hardening.md`
- Updated:
  - `lib/jido_conversation/operations.ex`
  - `lib/jido_conversation.ex`

## Quality gates

- `mix format`
- `mix test`
- `mix credo --strict`
- `mix dialyzer`
