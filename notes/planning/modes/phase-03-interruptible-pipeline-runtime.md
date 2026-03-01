# Phase 3 - Interruptible Pipeline Runtime

Back to index: [README](./README.md)

## Relevant Shared APIs / Interfaces
- Mode run orchestration contracts
- Runtime reducer/effect directives
- `JidoConversation.run/3`
- `JidoConversation.interrupt_run/2`
- `JidoConversation.resume_run/3`

## Relevant Assumptions / Defaults
- One active run per conversation.
- Step execution is driven through existing effect manager directives.
- Interrupt and resume are first-class lifecycle operations.

[ ] 3 Phase 3 - Interruptible Pipeline Runtime
  Implement a mode-agnostic, interruptible run engine mapped onto current deterministic runtime primitives.

  [ ] 3.1 Section - Run and Step Execution Model
    Define standard run and step contracts used by all modes.

    [ ] 3.1.1 Task - Define run lifecycle model
      Establish identifiers, statuses, transitions, and invariants.

      [ ] 3.1.1.1 Subtask - Define run identity fields and uniqueness constraints.
      [ ] 3.1.1.2 Subtask - Define statuses and legal transitions.
      [ ] 3.1.1.3 Subtask - Define terminal exclusivity and idempotency guarantees.

    [ ] 3.1.2 Task - Define step model and result envelopes
      Standardize step classes and outputs for orchestration logic.

      [ ] 3.1.2.1 Subtask - Define step classes (`:llm`, `:tool`, `:timer`, `:human_gate`, `:system`).
      [ ] 3.1.2.2 Subtask - Define step input and policy payload shapes.
      [ ] 3.1.2.3 Subtask - Define normalized step result and failure envelopes.

  [ ] 3.2 Section - Directive Mapping and Runtime Integration
    Map mode decisions into reducer/effect directives and lifecycle events.

    [ ] 3.2.1 Task - Implement run coordinator orchestration path
      Sequence mode callback decisions with reducer-applied events.

      [ ] 3.2.1.1 Subtask - Start run from run-request events and initialize run state.
      [ ] 3.2.1.2 Subtask - Feed effect lifecycle events back into mode callbacks.
      [ ] 3.2.1.3 Subtask - Emit run progress and terminal output directives.

    [ ] 3.2.2 Task - Implement step-to-effect directive conversion
      Reuse existing effect-manager pathways for execution and cancellation.

      [ ] 3.2.2.1 Subtask - Convert step definitions into `start_effect` payloads.
      [ ] 3.2.2.2 Subtask - Propagate policy and cause-link fields.
      [ ] 3.2.2.3 Subtask - Normalize effect lifecycle back into step lifecycle semantics.

  [ ] 3.3 Section - Interruption and Resume Mechanics
    Define and implement deterministic interruption and continuation behavior.

    [ ] 3.3.1 Task - Implement interruption protocol
      Ensure active runs can be interrupted safely and observably.

      [ ] 3.3.1.1 Subtask - Define interrupt request ingestion path and authorization checks.
      [ ] 3.3.1.2 Subtask - Cancel in-flight effects tied to the active run.
      [ ] 3.3.1.3 Subtask - Emit interrupted lifecycle events with reason metadata.

    [ ] 3.3.2 Task - Implement resume protocol
      Enable deterministic continuation of interrupted runs.

      [ ] 3.3.2.1 Subtask - Define resume preconditions and run lookup behavior.
      [ ] 3.3.2.2 Subtask - Rehydrate mode context from journaled state.
      [ ] 3.3.2.3 Subtask - Continue from last incomplete step with run ID continuity.

  [ ] 3.4 Section - Phase 3 Integration Tests
    Validate end-to-end run orchestration and interruption/resume correctness.

    [ ] 3.4.1 Task - Run orchestration integration scenarios
      Prove deterministic progress and terminalization behavior.

      [ ] 3.4.1.1 Subtask - Verify successful multi-step run completion.
      [ ] 3.4.1.2 Subtask - Verify failure terminalization and error projection behavior.
      [ ] 3.4.1.3 Subtask - Verify terminal exclusivity per run ID.

    [ ] 3.4.2 Task - Interruption and resume integration scenarios
      Prove safe cancellation and deterministic continuation under realistic timing races.

      [ ] 3.4.2.1 Subtask - Verify interrupt cancels active effects and marks run interrupted.
      [ ] 3.4.2.2 Subtask - Verify resume picks up from expected step.
      [ ] 3.4.2.3 Subtask - Verify duplicate interrupt/resume requests remain idempotent.
