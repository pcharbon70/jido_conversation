# Phase 11 rollout controller and transition recommendations

## Scope completed

- Added explicit rollout stage/controller config:
  - `rollout.stage`: `:shadow | :canary | :ramp | :full`
  - `rollout.controller.require_accept_streak`
  - `rollout.controller.rollback_stage`
- Added `JidoConversation.Rollout.Controller`:
  - computes staged recommendations from verification reports
  - recommendation actions:
    - `:promote`
    - `:hold`
    - `:rollback`
    - `:noop`
  - maps stage -> mode transitions:
    - `:shadow` => `:shadow`
    - `:canary | :ramp | :full` => `:event_based`
- Added rollout recommendation API:
  - `JidoConversation.rollout_recommend/1`
  - returns both verification report and controller recommendation
- Added helper to apply recommendations to rollout config:
  - `JidoConversation.Rollout.Controller.apply_recommendation/2`

## Migration control behavior

- `:accept` verification advances accept streak.
- Promotion requires `require_accept_streak` consecutive accepts.
- `:rollback_recommended` verification forces rollback to configured rollback stage.
- Full rollout stage returns `:noop` on further accepts.

## Files added/updated

- Added:
  - `lib/jido_conversation/rollout/controller.ex`
  - `test/jido_conversation/rollout_controller_test.exs`
  - `docs/phase_11_rollout_controller.md`
- Updated:
  - `config/config.exs`
  - `lib/jido_conversation/config.ex`
  - `lib/jido_conversation/operations.ex`
  - `lib/jido_conversation.ex`

