# ADR 0004: Durability and acknowledgment policy

- Status: Accepted
- Date: 2026-02-19
- Owners: jido_conversation maintainers

## Context

The system needs at-least-once delivery behavior with replay support and clear recovery
checkpoints. Ack points must be explicit to avoid data loss or hidden processing gaps.

## Decision

Ingress boundary policy:

- Normalize and validate incoming events.
- Append to journal before publishing to the bus.
- Acknowledge external ingress only after successful journal append and successful bus publish.

Runtime subscriber policy:

- Consume from bus with persistent subscriptions where reliability is required.
- Acknowledge consumed events only after reducer apply succeeds and `conv.applied.*`
  event emission is confirmed.

Checkpoint policy:

- Use journal/bus checkpoint ids as recovery anchors.
- On restart, resume from last committed checkpoint and replay forward.

Failure policy:

- Retry transient failures with bounded backoff.
- Route exhausted failures to DLQ with sufficient metadata for re-drive.

## Consequences

### Positive

- Durable ingest path and explicit apply-point accountability.
- Replay and restart behavior is deterministic and auditable.

### Negative

- Higher write and acknowledgment latency than best-effort fire-and-forget.
- Requires careful idempotency handling for at-least-once delivery.

## Alternatives considered

- Ack on bus receive before apply.
  - Rejected because failures after ack can create silent processing loss.
- Ack only after all side effects complete.
  - Rejected because it couples queue progress to long-running operations.
