# Phase 12 rollout manager and automated transition application

## Scope completed

- Added rollout manager runtime component:
  - `JidoConversation.Rollout.Manager` (GenServer)
  - tracks rollout evaluation state:
    - accept streak
    - last evaluation result
    - bounded recent evaluation history
    - evaluation count
    - applied transition count
- Added rollout manager config:
  - `rollout.manager.auto_apply`
  - `rollout.manager.max_history`
  - defaults are merged in config accessors and validated in `Config.validate!/0`
- Added rollout evaluation workflow:
  - evaluates verification from `Rollout.Reporter.snapshot/0`
  - computes controller recommendation from verification report
  - optionally applies rollout stage/mode updates to runtime config for:
    - `:promote`
    - `:rollback`
  - validates applied config and reverts env on apply failure
- Added operator/public APIs for manager controls:
  - `JidoConversation.rollout_manager_snapshot/0`
  - `JidoConversation.rollout_manager_reset/0`
  - `JidoConversation.rollout_evaluate/1`
- Added supervisor wiring:
  - manager now starts under `JidoConversation.Application`

## Behavioral notes

- `rollout_evaluate/1` is stateful and advances manager `accept_streak` from recommendation output.
- Apply behavior is opt-in per call (`apply?: true`) or configurable via `rollout.manager.auto_apply`.
- Manager snapshot reports current rollout stage/mode from active runtime config so operators can verify apply outcomes.

## Files added/updated

- Added:
  - `lib/jido_conversation/rollout/manager.ex`
  - `test/jido_conversation/rollout_manager_test.exs`
  - `docs/phase_12_rollout_manager.md`
- Updated:
  - `config/config.exs`
  - `lib/jido_conversation/application.ex`
  - `lib/jido_conversation/config.ex`
  - `lib/jido_conversation/operations.ex`
  - `lib/jido_conversation.ex`
