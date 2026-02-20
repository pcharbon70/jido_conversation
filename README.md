# Jido Conversation

Event-based conversation runtime prototype for an Elixir LLM coding assistant.

## Current status

- Phases 0-10 complete:
  - architecture baseline through reliability hardening
  - production launch-readiness reporting
  - launch-readiness trend storage for operational review

## Launch readiness

Use the operator report API to evaluate current launch state:

```elixir
JidoConversation.launch_readiness(
  max_queue_depth: 1_000,
  max_dispatch_failures: 0
)
```

Status values:

- `:ready` (no issues)
- `:warning` (non-critical issues detected)
- `:not_ready` (critical issues detected)

Store and review historical readiness snapshots:

```elixir
JidoConversation.record_launch_readiness_snapshot()
JidoConversation.launch_readiness_history(limit: 20)
```

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
