# Phase 7 - Cross-Mode Recovery and Determinism

Back to index: [README](./README.md)

## Relevant Shared APIs / Interfaces
- Runtime reducer and scheduler contracts
- Run interruption/resume APIs
- Journal replay and projection reconstruction paths

## Relevant Assumptions / Defaults
- Determinism and replay parity are mandatory.
- Cross-mode transitions must preserve isolation.
- Recovery behavior must be explicit for interrupted and in-flight runs.

[ ] 7 Phase 7 - Cross-Mode Recovery and Determinism
  Harden multi-mode runtime behavior under restarts, races, and high concurrency while preserving deterministic outcomes.

  [ ] 7.1 Section - Cross-Mode Transition and Preemption Policy
    Define strict behavior for mode/run overlap and explicit preemption cases.

    [ ] 7.1.1 Task - Implement run preemption policy
      Ensure only one active run executes and preemption remains explicit.

      [ ] 7.1.1.1 Subtask - Define queued-vs-rejected policy for second run requests.
      [ ] 7.1.1.2 Subtask - Define explicit preemption flow for forceful transitions.
      [ ] 7.1.1.3 Subtask - Define preemption event sequence and terminal guarantees.

    [ ] 7.1.2 Task - Implement transition guardrails
      Prevent invalid mode transitions and enforce handoff preconditions.

      [ ] 7.1.2.1 Subtask - Validate unsupported transitions are rejected consistently.
      [ ] 7.1.2.2 Subtask - Validate required handoff artifacts exist before guarded transitions.
      [ ] 7.1.2.3 Subtask - Validate transition decisions are journaled with causal links.

  [ ] 7.2 Section - Replay and Crash Recovery Semantics
    Ensure full rehydration of mode and run state from append-only journal.

    [ ] 7.2.1 Task - Extend replay reducer for mode run state
      Reconstruct active and historical runs deterministically.

      [ ] 7.2.1.1 Subtask - Rehydrate interrupted, failed, canceled, and completed run states.
      [ ] 7.2.1.2 Subtask - Rehydrate mode-specific artifacts and checkpoints.
      [ ] 7.2.1.3 Subtask - Rehydrate resumable step pointers with run identity continuity.

    [ ] 7.2.2 Task - Implement restart recovery strategy
      Define behavior for orphaned effects and partially applied runs.

      [ ] 7.2.2.1 Subtask - Detect and reconcile orphaned in-flight effects.
      [ ] 7.2.2.2 Subtask - Decide resume-or-terminalize behavior by run status.
      [ ] 7.2.2.3 Subtask - Emit explicit recovery lifecycle diagnostics.

  [ ] 7.3 Section - Concurrency, Isolation, and Scheduling Hardening
    Validate correctness under concurrent mode workloads and high runtime pressure.

    [ ] 7.3.1 Task - Harden isolation boundaries
      Guarantee no leakage across conversations/projects.

      [ ] 7.3.1.1 Subtask - Verify project-scoped locator isolation with shared conversation IDs.
      [ ] 7.3.1.2 Subtask - Verify effect cancellation isolation by conversation/run.
      [ ] 7.3.1.3 Subtask - Verify telemetry and projection partition integrity.

    [ ] 7.3.2 Task - Harden deterministic scheduling outcomes
      Preserve ordering and terminal exclusivity under burst load.

      [ ] 7.3.2.1 Subtask - Stress lifecycle ordering under high event throughput.
      [ ] 7.3.2.2 Subtask - Stress interrupt/resume race windows.
      [ ] 7.3.2.3 Subtask - Verify no duplicate terminal events for a run.

  [ ] 7.4 Section - Phase 7 Integration Tests
    Validate replay parity, crash recovery, and cross-mode concurrency guarantees.

    [ ] 7.4.1 Task - Replay and recovery integration scenarios
      Prove deterministic reconstruction and restart-safe behavior.

      [ ] 7.4.1.1 Subtask - Verify replay parity for completed and interrupted runs.
      [ ] 7.4.1.2 Subtask - Verify crash recovery of in-flight mode runs.
      [ ] 7.4.1.3 Subtask - Verify recovery diagnostics and lifecycle events.

    [ ] 7.4.2 Task - Concurrency and isolation integration scenarios
      Prove high-concurrency correctness and strict boundary isolation.

      [ ] 7.4.2.1 Subtask - Verify concurrent runs across many conversations/projects.
      [ ] 7.4.2.2 Subtask - Verify guarded transitions under concurrent control requests.
      [ ] 7.4.2.3 Subtask - Verify terminal-event exclusivity across all modes.
