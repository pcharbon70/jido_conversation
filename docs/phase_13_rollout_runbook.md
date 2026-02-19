# Phase 13 rollout runbook assessment and operator actions

## Scope completed

- Added rollout runbook assessment module:
  - `JidoConversation.Rollout.Runbook`
  - performs a stateful rollout evaluation through `Rollout.Manager`
  - classifies rollout gate state for operators:
    - `:disabled`
    - `:hold`
    - `:promotion_ready`
    - `:steady_state`
    - `:rollback_required`
- Added trigger extraction for rollback incident response:
  - `:parity_mismatch_rate_exceeded`
  - `:drop_rate_exceeded`
  - `:legacy_unavailable_rate_exceeded`
- Added structured operator action items per gate:
  - promotion actions
  - rollback/incident actions
  - hold-volume collection actions
  - disabled and steady-state actions

## Public and operator APIs added

- `JidoConversation.rollout_runbook_assess/1`
- `JidoConversation.Operations.rollout_runbook_assess/1`

## Behavioral notes

- Runbook assessment builds on manager evaluation state, so accept streak and evaluation history continue to advance through normal rollout checks.
- Assessment supports optional apply behavior through the same `apply?` option used by the rollout manager.
- Action items are structured as maps (`action`, `reason`, `priority`) to support automation and dashboards.

## Files added/updated

- Added:
  - `lib/jido_conversation/rollout/runbook.ex`
  - `test/jido_conversation/rollout_runbook_test.exs`
  - `docs/phase_13_rollout_runbook.md`
- Updated:
  - `lib/jido_conversation/operations.ex`
  - `lib/jido_conversation.ex`
