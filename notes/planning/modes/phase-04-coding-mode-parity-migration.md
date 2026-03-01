# Phase 4 - Coding Mode Parity Migration

Back to index: [README](./README.md)

## Relevant Shared APIs / Interfaces
- `JidoConversation.send_and_generate/3`
- `JidoConversation.generate_assistant_reply/2`
- `JidoConversation.await_generation/3`
- `JidoConversation.cancel_generation/2`
- `:coding` mode pipeline

## Relevant Assumptions / Defaults
- Existing coding behavior remains the baseline contract.
- Migration is implementation-internal, not user-facing breaking.
- Parity is validated by behavior and telemetry expectations.

[ ] 4 Phase 4 - Coding Mode Parity Migration
  Replace the implicit single coding path with explicit `:coding` mode execution while preserving existing contracts.

  [ ] 4.1 Section - Coding Mode Pipeline Definition
    Encode the current coding flow as explicit mode steps and outputs.

    [ ] 4.1.1 Task - Define coding mode step graph
      Capture current request, generation, tool handling, and completion flow.

      [ ] 4.1.1.1 Subtask - Define context assembly and LLM request step.
      [ ] 4.1.1.2 Subtask - Define tool-execution and tool-result feedback steps.
      [ ] 4.1.1.3 Subtask - Define assistant-message commit and completion artifact step.

    [ ] 4.1.2 Task - Define coding defaults and policies
      Preserve current default behavior for backend selection, skills, and cancellation.

      [ ] 4.1.2.1 Subtask - Define default LLM/backend/model policy for coding mode.
      [ ] 4.1.2.2 Subtask - Define default skill activation profile.
      [ ] 4.1.2.3 Subtask - Define default timeout and cancel reason semantics.

  [ ] 4.2 Section - Legacy API Delegation to Coding Mode
    Route existing high-level APIs through coding mode runtime without contract drift.

    [ ] 4.2.1 Task - Delegate synchronous coding entrypoint
      Ensure `send_and_generate/3` executes through mode runtime while preserving tuple contract.

      [ ] 4.2.1.1 Subtask - Preserve success tuple shape and message-ordering behavior.
      [ ] 4.2.1.2 Subtask - Preserve timeout behavior and cancel-on-timeout defaults.
      [ ] 4.2.1.3 Subtask - Preserve backend error mapping behavior.

    [ ] 4.2.2 Task - Delegate async generation/await path
      Ensure generation reference and await semantics remain compatible.

      [ ] 4.2.2.1 Subtask - Preserve generation reference semantics and caller notification routing.
      [ ] 4.2.2.2 Subtask - Preserve re-await behavior after timeout with and without cancellation.
      [ ] 4.2.2.3 Subtask - Preserve cancellation propagation and derived-state transitions.

  [ ] 4.3 Section - Parity Guardrails and Regression Matrix
    Establish explicit parity matrix and non-functional guardrails before adding new modes.

    [ ] 4.3.1 Task - Build behavioral parity matrix
      Compare legacy and mode-driven coding behavior across all core cases.

      [ ] 4.3.1.1 Subtask - Cover success, provider error, and unknown error flows.
      [ ] 4.3.1.2 Subtask - Cover timeout cancel/no-cancel and guard-recovery flows.
      [ ] 4.3.1.3 Subtask - Cover cancel reason propagation and concurrency-guard behavior.

    [ ] 4.3.2 Task - Build telemetry and stability parity checks
      Ensure internal migration does not degrade operations.

      [ ] 4.3.2.1 Subtask - Validate telemetry event cardinality parity.
      [ ] 4.3.2.2 Subtask - Validate latency and queue-depth regression thresholds.
      [ ] 4.3.2.3 Subtask - Validate cleanup of canceled/failed runs and effects.

  [ ] 4.4 Section - Phase 4 Integration Tests
    Validate coding-mode migration and external API compatibility end-to-end.

    [ ] 4.4.1 Task - Coding mode parity integration scenarios
      Prove coding mode behavior matches existing runtime expectations.

      [ ] 4.4.1.1 Subtask - Verify full success path with assistant output commit.
      [ ] 4.4.1.2 Subtask - Verify backend failure path with unchanged assistant history.
      [ ] 4.4.1.3 Subtask - Verify timeout/cancel and re-await behavior parity.

    [ ] 4.4.2 Task - Delegated API integration scenarios
      Prove existing public entrypoints remain stable.

      [ ] 4.4.2.1 Subtask - Verify `send_and_generate/3` contract parity.
      [ ] 4.4.2.2 Subtask - Verify `generate_assistant_reply/2` + `await_generation/3` parity.
      [ ] 4.4.2.3 Subtask - Verify `cancel_generation/2` behavior against active coding runs.
