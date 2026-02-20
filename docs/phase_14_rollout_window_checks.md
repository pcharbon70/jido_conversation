# Phase 14 post-rollout verification windows and acceptance checks

## Scope completed

- Added rollout acceptance window assessment module:
  - `JidoConversation.Rollout.Window`
  - evaluates recent rollout assessments in a time-bounded window
  - classifies window status:
    - `:insufficient_data`
    - `:monitor`
    - `:accepted`
    - `:rejected`
- Added rollout window policy configuration:
  - `rollout.window.window_minutes`
  - `rollout.window.min_assessments`
  - `rollout.window.required_accept_count`
  - `rollout.window.max_rollback_count`
- Added threshold-aware window metrics:
  - assessment count
  - accept/hold/rollback counts
  - applied transition count
- Added window action-item mapping for operations:
  - collect more observations
  - continue monitoring
  - mark acceptance window passed
  - execute rollback runbook and incident response

## Public and operator APIs added

- `JidoConversation.rollout_window_assess/1`
- `JidoConversation.Operations.rollout_window_assess/1`

## Behavioral notes

- Window checks are built from recent rollout manager evaluation history.
- `rollout_window_assess/1` first performs a fresh runbook assessment, then evaluates window status over the configured lookback period.
- Rejections are triggered when rollback count breaches threshold, regardless of accept count.

## Files added/updated

- Added:
  - `lib/jido_conversation/rollout/window.ex`
  - `test/jido_conversation/rollout_window_test.exs`
  - `docs/phase_14_rollout_window_checks.md`
- Updated:
  - `config/config.exs`
  - `lib/jido_conversation/config.ex`
  - `lib/jido_conversation/operations.ex`
  - `lib/jido_conversation.ex`
