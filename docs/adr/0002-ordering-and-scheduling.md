# ADR 0002: Record ordering vs processing ordering

- Status: Accepted
- Date: 2026-02-19
- Owners: jido_conversation maintainers

## Context

Conversation events must remain fully auditable while still allowing priority handling
for interrupts and state-critical events. Strict FIFO processing for all event types
creates latency and responsiveness issues under token-delta or progress-event load.

## Decision

- Preserve immutable record order in the journal (append order).
- Allow runtime processing order to differ from record order using a deterministic
  scheduler function.
- Implement scheduler contract as `schedule(queue, state) -> next_event`.
- Scheduler must be deterministic based on:
  - event priority class
  - causal readiness
  - fairness policy
- Emit `conv.applied.*` markers when the reducer successfully applies an event.

## Runtime shape decision

- Use partitioned workers keyed by hash(`subject`) as the default runtime topology.
- Avoid one persistent bus subscriber per conversation.

## Consequences

### Positive

- Clear split between audit order and responsiveness behavior.
- Replay can reproduce reducer state transitions using the same scheduler rules.
- Partitioning scales conversations horizontally while preserving per-conversation locality.

### Negative

- Scheduler implementation and tests are now first-class critical logic.
- Operators need visibility into both journal order and applied order.

## Alternatives considered

- Strict FIFO processing only.
  - Rejected because control-plane events can be delayed by high-volume low-value events.
- One process and subscriber per conversation.
  - Rejected as default because it increases subscription overhead and scaling risk.
