# Phase 16 rollout settings runtime controls

## Scope completed

- Added runtime rollout settings module:
  - `JidoConversation.Rollout.Settings`
  - provides validated runtime updates for rollout config
- Added rollout settings snapshot and controls:
  - `snapshot/0`
  - `set_minimal_mode/2`
  - `set_mode/1`
  - `set_stage/1`
  - `configure/2`
- Added safety behavior:
  - non-`event_based` modes are rejected while `minimal_mode` is enabled
  - enabling minimal mode forces mode to `:event_based` by default
  - invalid runtime updates are reverted automatically

## Public and operator APIs added

- `JidoConversation.rollout_settings_snapshot/0`
- `JidoConversation.rollout_set_minimal_mode/2`
- `JidoConversation.rollout_set_mode/1`
- `JidoConversation.rollout_set_stage/1`
- `JidoConversation.rollout_configure/2`

## Test coverage

- Added rollout settings tests for:
  - snapshot shape
  - minimal mode enable/disable transitions
  - mode guard while minimal mode is enabled
  - stage update path
  - invalid config rollback/revert behavior

## Files added/updated

- Added:
  - `lib/jido_conversation/rollout/settings.ex`
  - `test/jido_conversation/rollout_settings_test.exs`
  - `docs/phase_16_rollout_settings_controls.md`
- Updated:
  - `lib/jido_conversation/operations.ex`
  - `lib/jido_conversation.ex`
