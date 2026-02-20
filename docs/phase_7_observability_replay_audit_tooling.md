# Phase 7 observability, replay, and audit tooling

## Scope completed

- Added runtime telemetry instrumentation:
  - queue depth (`[:jido_conversation, :runtime, :queue, :depth]`)
  - reducer apply latency (`[:jido_conversation, :runtime, :apply, :stop]`)
  - control-plane latency for abort/stop/cancel requests
    (`[:jido_conversation, :runtime, :abort, :latency]`)
- Extended configured telemetry subscriptions to include:
  - subscription retry attempts
  - subscription DLQ events
  - runtime internal metrics above
- Reworked `JidoConversation.Telemetry` into an operational metrics aggregator:
  - queue depth by partition and total depth
  - apply latency summary
  - abort latency summary
  - retry, DLQ, and dispatch failure counters
  - latest dispatch failure metadata
- Added operator tooling module `JidoConversation.Operations`:
  - `replay_conversation/2`
  - `trace_cause_effect/2`
  - `record_audit_trace/3`
  - `stream_subscriptions/0`
  - `checkpoints/0`
  - stream subscribe/unsubscribe helpers including pubsub/webhook convenience APIs
- Added root API wrappers in `JidoConversation` for telemetry snapshot and operations.

## Audit projection behavior

- Added audit event recording via `record_audit_trace/3`:
  - emits `conv.audit.trace.chain_recorded`
  - includes required audit contract fields:
    - `audit_id`
    - `category`
  - includes trace metadata for operator forensics (direction, length, signal IDs)

## Tests added

- `test/jido_conversation/telemetry_test.exs`
  - validates metric aggregation and reset behavior
- `test/jido_conversation/operations_test.exs`
  - validates replay filtering by conversation
  - validates cause/effect trace and audit emission
  - validates subscription and checkpoint inspection

## Quality gates

- `mix format`
- `mix test`
- `mix credo --strict`
- `mix dialyzer`
