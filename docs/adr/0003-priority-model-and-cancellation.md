# ADR 0003: Priority model and cancellation semantics

- Status: Accepted
- Date: 2026-02-19
- Owners: jido_conversation maintainers

## Context

Abort/stop actions must be near-immediate even while streaming or tool activity is high.
This requires explicit priority classes and strict separation between pure state
transitions and long-running side effects.

## Decision

Priority classes:

- `P0` interrupt/control-plane: abort, cancel, stop generation, permission revoke
- `P1` state-critical: prompt received, tool result/error, LLM step completion
- `P2` state-informative: tool started/stopped, progress updates, LLM started
- `P3` high-volume/low-criticality: token deltas, heartbeat/progress ticks

Cancellation and reducer semantics:

- Reducers must remain non-blocking and side-effect free.
- Reducers emit directives; effect workers do long-running work.
- `P0` events preempt lower-priority work at scheduling boundaries.
- Abort events must cancel in-flight workers and remove in-flight references from state.
- Effect workers must emit lifecycle events (`started`, `progress`, `completed`,
  `failed`, `canceled`) back into the same event flow.

## Consequences

### Positive

- Fast control-plane responsiveness.
- Deterministic and testable state transitions.
- Uniform observability for effect lifecycles.

### Negative

- Requires strict discipline to keep reducer pure.
- Requires robust worker tracking and cancellation wiring.

## Alternatives considered

- Running tools/LLM calls directly in reducer process.
  - Rejected because it blocks scheduling and weakens abort responsiveness.
- No explicit priority classes.
  - Rejected because behavior under load becomes unpredictable.
