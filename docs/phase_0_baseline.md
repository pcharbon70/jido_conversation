# Phase 0 baseline completion

This document tracks the concrete phase-0 implementation artifacts.

## Scope completed

- Architecture decisions codified as ADRs.
- Event stream taxonomy and naming conventions documented.
- Initial SLO and error-budget baseline documented.
- Initial failure-mode matrix documented.

## Artifacts

- `docs/adr/0001-conversation-identity-and-envelope.md`
- `docs/adr/0002-ordering-and-scheduling.md`
- `docs/adr/0003-priority-model-and-cancellation.md`
- `docs/adr/0004-durability-and-ack-policy.md`
- `docs/architecture/event_stream_taxonomy.md`
- `docs/operations/slo_and_error_budget.md`
- `docs/operations/failure_mode_matrix.md`

## Deferred to phase 1+

- Runtime supervision wiring and config modules.
- Contract validation implementation in code.
- Persistent subscription and checkpoint implementation.
- Reducer and scheduler modules.
