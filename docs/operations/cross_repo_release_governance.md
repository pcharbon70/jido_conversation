# Cross-Repo Release Governance

This guide defines release and rollback expectations for the split architecture:

- `jido_conversation`: conversation substrate (contract, runtime, projections)
- `jido_code_server`: mode orchestration, policy, and execution gateway

## Migration Notes: In-Library Modes to Code-Server Orchestration

Previous direction: mode-specific business logic was being considered inside the
conversation library. Current direction: mode logic is fully owned by
`jido_code_server`.

Migration implications:

1. Keep `jido_conversation` APIs focused on canonical events and projections.
2. Send orchestration traffic (`conversation.user.message`, tool lifecycle,
   cancel/resume) through `jido_code_server` conversations.
3. Treat `jido_conversation` as the canonical journal substrate and replay
   source, not the mode decision engine.

## Release Checklist (Cross-Repo)

1. Shared fixture contract gates pass in both repositories.
2. Determinism and restart parity tests pass for orchestration flows.
3. Cancellation/resume behavior is validated across async tool paths.
4. Documentation in both repositories matches the same ownership boundary.
5. Migration and rollback notes are published with the release tag.

## Known Limitations and Follow-Up

- Mode templates are currently baseline presets; deeper per-project customization
  still requires explicit configuration work.
- Strategy adapters are centralized but not all teams may yet have dedicated
  runner modules.
- Cross-repo drift tests currently focus on representative traces rather than
  exhaustive production traffic shapes.

Planned follow-up:

1. Expand shared fixture coverage per mode and per execution kind.
2. Add stricter release gates for fixture drift-injection simulations.
3. Add automated changelog checks for execution-kind contract updates.

## Rollback and Mitigation Playbook

If critical regressions are detected after release:

1. Freeze new mode/strategy changes and branch hotfix from the latest stable
   tags in both repos.
2. Revert to the last known-good release pair where cross-repo contract gates
   were green.
3. Keep journal data untouched; rely on replay to validate state continuity
   after rollback.
4. Restrict runtime to conservative mode settings (for example, `:coding`
   baseline only) until remediation is merged.
5. Publish incident summary with root cause, blast radius, and replay evidence.
