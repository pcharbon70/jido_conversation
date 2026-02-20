# Design Principles

This library follows a small set of architectural rules. Most implementation
choices should map directly to one or more of these principles.

## 1. Event-first boundaries

- The canonical envelope is `Jido.Signal`.
- `subject` is the conversation identity.
- All ingress passes the contract boundary before entering runtime.

Why:

- Keeps all producers on one transport-neutral model
- Makes replay, correlation, and audit queries consistent

Reference: `docs/adr/0001-conversation-identity-and-envelope.md`

## 2. Journal-first durability

- Ingest path is: normalize/validate -> journal append -> bus publish.
- Publish happens only after journal record succeeds.

Why:

- Preserves durable traceability
- Avoids silent data loss between ingress and processing

Reference: `docs/adr/0004-durability-and-ack-policy.md`

## 3. Deterministic runtime core

- Scheduler is deterministic and pure for a given queue/state.
- Reducer is pure and non-blocking.
- Long-running work is emitted as directives, never run inline in reducer logic.

Why:

- Ensures replay parity and predictable behavior
- Keeps control-plane responsiveness under load

References:

- `docs/adr/0002-ordering-and-scheduling.md`
- `docs/adr/0003-priority-model-and-cancellation.md`

## 4. Separate record order from processing order

- Journal append order is immutable audit order.
- Processing order may differ due to priority, causality, and fairness policy.

Why:

- Supports both auditability and runtime responsiveness

## 5. Explicit control-plane priority

- Interrupt signals (`abort`, `stop`, `cancel`) are highest priority.
- Fairness guarantees lower-priority ready events eventually run.

Why:

- Prevents starvation and preserves user-facing control latency targets

## 6. Host-owned operations policy

- This library exposes telemetry and runtime primitives.
- Deployment/readiness policy belongs in host applications.

Why:

- Keeps this package reusable as an embeddable runtime
- Avoids hard-coding one organization’s operations model

Reference: `docs/host_integration_patterns.md`
