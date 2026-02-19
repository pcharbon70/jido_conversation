# Jido Conversation

Event-based conversation runtime prototype for an Elixir LLM coding assistant.

## Current status

- Phases 0-13 complete:
  - architecture baseline through reliability hardening
  - rollout migration, verification, controller, manager, and runbook tooling

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
