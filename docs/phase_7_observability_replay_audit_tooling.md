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
- Added root API wrapper in `JidoConversation` for telemetry snapshot.

## Tests added

- `test/jido_conversation/telemetry_test.exs`
  - validates metric aggregation and reset behavior

## Quality gates

- `mix format`
- `mix test`
- `mix credo --strict`
- `mix dialyzer`
