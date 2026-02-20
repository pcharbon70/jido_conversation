# Phase 15 greenfield minimal mode

## Scope completed

- Added rollout minimal-mode policy switch:
  - `rollout.minimal_mode` (boolean)
  - defaults to `true` in shared config for greenfield operation
- Added config accessor/validation:
  - `JidoConversation.Config.rollout_minimal_mode?/0`
  - validation for `rollout.minimal_mode`
- Updated rollout decision policy:
  - when minimal mode is enabled, `Rollout.decide/1` always returns:
    - `mode: :event_based`
    - `action: :enqueue_runtime`
    - `reason: :minimal_mode_enabled`
  - canary/parity/disabled rollout gating is bypassed
- Updated runtime ingress processing:
  - `IngressSubscriber` now short-circuits rollout reporter + parity sampling in minimal mode
  - normalized events are enqueued directly to runtime coordinator
- Preserved advanced rollout tooling for future use:
  - setting `rollout.minimal_mode: false` restores full rollout behavior

## Test behavior and coverage

- Test environment now sets `rollout.minimal_mode: false` so existing rollout suites continue validating advanced controls.
- Added dedicated minimal-mode tests for:
  - bypass behavior when rollout mode is otherwise disabled
  - restoring advanced rollout gating when minimal mode is disabled

## Files added/updated

- Added:
  - `docs/phase_15_minimal_mode.md`
  - `test/jido_conversation/rollout_minimal_mode_test.exs`
- Updated:
  - `config/config.exs`
  - `config/test.exs`
  - `lib/jido_conversation/config.ex`
  - `lib/jido_conversation/rollout.ex`
  - `lib/jido_conversation/runtime/ingress_subscriber.ex`
  - `README.md`
