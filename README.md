# Jido Conversation

Event-based conversation runtime prototype for an Elixir LLM coding assistant.

## Current status

- Phases 0-26 complete:
  - architecture baseline through reliability hardening
  - replay-vs-live determinism parity hardening
- Post-phase hardening complete:
  - cross-namespace contract evolution test matrix for v1 compatibility
  - scheduler fairness/load burst test coverage
  - host integration patterns for observability and deployment policy
  - replay-stress suites with larger sampled traces
  - LLM adapter retryability policy hardening for non-retryable `4xx` errors
  - runtime retry-policy matrix coverage for built-in LLM adapters
  - stream-path runtime retry-policy matrix coverage for built-in LLM adapters
  - retry telemetry parity coverage for built-in LLM adapters
  - stream retry telemetry parity coverage for built-in LLM adapters
  - cancel telemetry parity coverage across built-in LLM adapters
  - timeout/transport retry category telemetry parity across built-in adapters
  - stream timeout/transport retry category telemetry parity across built-in adapters
  - auth non-retryable runtime parity coverage across built-in adapters
  - stream auth non-retryable runtime parity coverage across built-in adapters
  - unknown non-retryable runtime parity coverage across built-in adapters
  - stream unknown non-retryable runtime parity coverage across built-in adapters
  - config non-retryable runtime parity coverage across built-in adapters
  - stream config non-retryable runtime parity coverage across built-in adapters
  - canceled non-retryable runtime parity coverage across built-in adapters
  - stream canceled non-retryable runtime parity coverage across built-in adapters

## Library scope

`jido_conversation` is an embeddable runtime library.

Core public APIs focus on:

- event ingestion (`JidoConversation.ingest/2`)
- conversation projections (`JidoConversation.timeline/2`, `JidoConversation.llm_context/2`)
- runtime diagnostics (`JidoConversation.health/0`, `JidoConversation.telemetry_snapshot/0`)

## Local setup

1. Install tool versions from `.tool-versions`.
2. Install dependencies:

```bash
mix deps.get
```

3. Run tests:

```bash
mix test
```

4. Run lint/quality checks:

```bash
mix quality
```

## Example app

Run the standalone terminal chat example from the repo root:

```bash
mix terminal_chat
```

## Git hooks

This repository uses a tracked hook script in `.githooks/pre-commit`.

Configure local Git to use it:

```bash
git config core.hooksPath .githooks
```

The hook runs:

- `mix test`
- `mix credo --strict`
- `mix dialyzer`

## Research and implementation plan

- Research: `notes/research/events_based_conversation.md`
- Implementation plan: `notes/research/events_based_architecture_implementation_plan.md`
- Host integration patterns: `docs/host_integration_patterns.md`
- Replay stress suites: `docs/replay_stress_suites.md`
- User guides: `docs/user/README.md`
- Developer guides: `docs/developer/README.md`
