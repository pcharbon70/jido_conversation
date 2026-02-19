# Phase 10 rollout verification and acceptance automation

## Scope completed

- Added rollout verification thresholds to runtime configuration:
  - `rollout.verification.min_runtime_decisions`
  - `rollout.verification.min_parity_reports`
  - `rollout.verification.max_mismatch_rate`
  - `rollout.verification.max_legacy_unavailable_rate`
  - `rollout.verification.max_drop_rate`
- Added verification engine:
  - `JidoConversation.Rollout.Verification.evaluate/2`
  - computes normalized rollout metrics and returns a rollout verdict:
    - `:accept`
    - `:hold`
    - `:rollback_recommended`
  - emits structured reasons for each non-accept verdict.
- Extended rollout reporter snapshot with aggregate parity status counts:
  - `match`
  - `mismatch`
  - `legacy_unavailable`
- Added operator-facing API:
  - `JidoConversation.rollout_verify/1`
- Added test coverage for verification decisions and API integration.

## Acceptance semantics implemented

- `:accept`: thresholds satisfied with sufficient runtime/parity volume.
- `:hold`: insufficient migration signal quality/volume or excessive legacy-unavailable rate.
- `:rollback_recommended`: parity mismatch or drop rate exceeds configured thresholds.

## Files added/updated

- Added:
  - `lib/jido_conversation/rollout/verification.ex`
  - `test/jido_conversation/rollout_verification_test.exs`
  - `docs/phase_10_rollout_verification.md`
- Updated:
  - `config/config.exs`
  - `lib/jido_conversation/config.ex`
  - `lib/jido_conversation/rollout/reporter.ex`
  - `lib/jido_conversation/operations.ex`
  - `lib/jido_conversation.ex`

