# ADR 0001: Conversation identity and event envelope

- Status: Accepted
- Date: 2026-02-19
- Owners: jido_conversation maintainers

## Context

The architecture requires a stable conversation identity across messaging ingress, tools,
LLM runtime, control-plane actions, replay, and audits. We also need one canonical
event format at system boundaries so every component can process events consistently.

## Decision

- Use `Jido.Signal` as the canonical event envelope.
- Treat these envelope fields as required for all events at ingress boundaries:
  - `type`
  - `source`
  - `id`
  - `subject`
- Use `subject` as the canonical `conversation_id`.
- Use `cause_id` when an event is derived from another event to preserve causality.
- Reject events that do not pass envelope validation.

## Consequences

### Positive

- One correlation mechanism across journal, bus, runtime, and observability.
- Replay and audit queries can group by one canonical key.
- Integrations can be added without per-adapter envelope contracts.

### Negative

- Adapters must normalize incoming data before publishing.
- Existing producers that do not set `subject` must be updated.

## Alternatives considered

- Independent `conversation_id` field in payload instead of `subject`.
  - Rejected because grouping at envelope level is clearer and aligns with journal usage.
- Multiple envelope shapes by source type.
  - Rejected because it increases boundary complexity and validation branching.
