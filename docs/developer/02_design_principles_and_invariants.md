# 02. Design Principles and Invariants

These rules explain why the system is structured the way it is and what must
remain true when changing code.

## Core principles

1. Reducer purity
   - `Runtime.Reducer` must not perform I/O or process operations.
   - It returns only new state plus directives.

2. Journal-first event model
   - Inbound events are validated and recorded before runtime processing.
   - Replay/debugging rely on journal order.

3. Deterministic scheduling
   - Runtime processing order may differ from append order.
   - Selection still follows deterministic scheduler rules.

4. Explicit effect boundaries
   - Side effects run in `EffectWorker` processes managed by `EffectManager`.
   - Lifecycle is expressed as `conv.effect.*` events.

5. Projection from events
   - Read models (`Timeline`, `LlmContext`) are derived from ingested events.
   - No hidden mutable projection stores in core runtime.

## Contract invariants

- Stream namespace must match `conv.in|applied|effect|out|audit.*`.
- `extensions.contract_major` must be supported (`1`).
- Stream-family payload keys are required by `Signal.Contract`.

## Runtime invariants

- Partition routing depends on conversation `subject`.
- `PartitionWorker` is the boundary where directives are executed.
- Effect retries/timeouts/cancellation are encoded via lifecycle events.

## Observability invariants

- LLM retry categories are normalized and tracked in telemetry.
- Health endpoint must reflect bus/coordinator/supervisor liveness.
- Snapshot metrics must remain safe to call from host polling loops.
