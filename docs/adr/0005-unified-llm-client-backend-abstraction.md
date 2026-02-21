# ADR 0005: Unified LLM client with backend adapters

- Status: Accepted
- Date: 2026-02-21
- Owners: jido_conversation maintainers

## Context

`jido_conversation` currently models LLM work as runtime effects, but its core effect
execution path does not provide a unified backend abstraction for real provider calls.
In the Jido ecosystem, two viable LLM execution paths already exist:

- `JidoAI` (direct model/provider access, powered by ReqLLM)
- `JidoHarness` (coding CLI orchestration with provider/model controlled by CLI runtime)

We need one internal LLM integration surface inside `jido_conversation` so host apps
can use either path without changing reducer/runtime contracts.

## Decision

- Add a unified internal LLM client namespace in `jido_conversation`.
- Implement backend adapters:
  - `:jido_ai`
  - `:harness`
- Keep runtime architecture boundaries:
  - reducer remains pure and backend-agnostic
  - effect worker performs backend side effects
  - lifecycle state flows through `conv.effect.*` events
- Normalize backend-native outputs to canonical lifecycle categories:
  - started
  - delta (content/thinking)
  - completed
  - failed
  - canceled
- Ownership of provider/model selection:
  - `JidoAI` path: `jido_conversation` supports provider/model selection inputs
  - `Harness` path: provider/model selection is owned by coding CLI/runtime config
- Cancellation semantics:
  - runtime cancel requests must invoke backend-specific cancellation where possible
  - cancellation is best effort at backend boundary
  - runtime always emits normalized canceled lifecycle when cancellation is accepted
- Error semantics:
  - backend errors are normalized into stable categories for retries/telemetry
  - retryability is decided by normalized category, not raw provider shape

## Consequences

### Positive

- One stable LLM integration contract for runtime code and tests.
- Backend choice can change without reducer/projection rewrites.
- Consistent lifecycle and telemetry behavior across JidoAI and Harness paths.
- Clear model/provider ownership boundaries prevent duplicated routing policy.

### Negative

- Additional adapter/normalization layer increases implementation surface.
- Optional backend dependencies require explicit config and validation handling.
- Event shape mapping for Harness providers needs robust fallback logic.

## Alternatives considered

- Keep LLM execution entirely outside `jido_conversation`.
  - Rejected because runtime effect/cancellation semantics become fragmented and
    host integrations duplicate orchestration logic.
- Hardcode only one backend (JidoAI or Harness).
  - Rejected because it removes required flexibility for ecosystem use cases.
- Execute backend calls directly from reducer transitions.
  - Rejected because it violates reducer purity and determinism constraints.
