# Phase 9 rollout and migration

## Scope completed

- Added rollout feature-flag policy for runtime migration:
  - modes: `:event_based | :shadow | :disabled`
  - progressive canary filtering by `subject`, `tenant_id`, and `channel`
  - parity sampling controls with deterministic sampling by signal id
- Added rollout reporter process:
  - decision counters (`enqueue_runtime`, `parity_only`, `drop`)
  - reason counters
  - bounded recent parity samples
  - bounded recent parity reports
- Added parity comparison tooling with pluggable legacy adapter:
  - default no-op legacy adapter (`legacy_adapter_not_configured`)
  - multiset parity comparison between `conv.out.**` replay and legacy outputs
  - persisted parity reports via rollout reporter
- Integrated rollout policy into ingress runtime routing:
  - ingress now gates enqueueing based on rollout decision
  - shadow mode enables parity-only flow without runtime enqueue

## Operator APIs added

- `JidoConversation.rollout_snapshot/0`
- `JidoConversation.rollout_reset/0`
- `JidoConversation.rollout_parity_compare/2`

## Migration runbook baseline

1. Set `rollout.mode` to `:shadow`.
2. Enable canary filter for a small subject/tenant/channel set.
3. Enable parity sampling and configure a real legacy adapter.
4. Run `rollout_parity_compare/2` for canary conversations and inspect mismatch counts.
5. Move canary traffic to `rollout.mode: :event_based` progressively.
6. Expand allowlists in stages and monitor `rollout_snapshot/0` counters.
7. If parity mismatch/error rates breach threshold, switch to `rollout.mode: :disabled` and execute rollback.

## Rollback triggers (initial)

- parity mismatch rate above threshold during canary window
- unexpected drop growth in rollout reason counters
- sustained dispatch/retry/DLQ regression against phase-8 baseline

## Files added/updated

- Added:
  - `lib/jido_conversation/rollout.ex`
  - `lib/jido_conversation/rollout/reporter.ex`
  - `lib/jido_conversation/rollout/parity.ex`
  - `lib/jido_conversation/rollout/parity_adapter.ex`
  - `lib/jido_conversation/rollout/parity/noop_legacy_adapter.ex`
  - `test/jido_conversation/rollout_test.exs`
  - `docs/phase_9_rollout_migration.md`
- Updated:
  - `lib/jido_conversation/application.ex`
  - `lib/jido_conversation/config.ex`
  - `lib/jido_conversation/runtime/ingress_subscriber.ex`
  - `lib/jido_conversation/operations.ex`
  - `lib/jido_conversation.ex`
  - `config/config.exs`

