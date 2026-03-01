# Phase 5 - Pipeline Step Engine and Interruptibility

Back to index: [README](./README.md)

## Relevant Shared APIs / Interfaces
- `Jido.Code.Server.Conversation.Domain.Reducer`
- `Jido.Code.Server.Conversation.Actions.Support`
- `Jido.Code.Server.Conversation.Instructions.RunExecutionInstruction` (new)
- `Jido.Code.Server.Project.ExecutionRunner`

## Relevant Assumptions / Defaults
- Mode execution is modeled as deterministic step pipelines.
- Pipeline steps are reducer-planned and executed through one execution gateway pathway.
- One active run per conversation remains the default.

[ ] 5 Phase 5 - Pipeline Step Engine and Interruptibility
  Implement the mode pipeline engine in `jido_code_server` so mode behavior executes as interruptible, deterministic step transitions.

  [ ] 5.1 Section - Pipeline Run Model and Step Planning
    Define pipeline run lifecycle and step planning logic as pure reducer behavior.

    [ ] 5.1.1 Task - Define step/run state contracts
      Represent pipeline progress as explicit run and step snapshots in domain state.

      [ ] 5.1.1.1 Subtask - Define step identity, status, retry counters, and predecessor relationships.
      [ ] 5.1.1.2 Subtask - Define run-level status transitions (`pending`, `running`, `interrupted`, `completed`, `failed`, `canceled`).
      [ ] 5.1.1.3 Subtask - Define deterministic serialization for run/step snapshots and history.

    [ ] 5.1.2 Task - Implement reducer-driven step planner
      Convert input and lifecycle signals into next-step intents without side effects.

      [ ] 5.1.2.1 Subtask - Define planner rules for start, continue, retry, and terminate decisions.
      [ ] 5.1.2.2 Subtask - Define no-op and conflict resolution rules for duplicate/out-of-order events.
      [ ] 5.1.2.3 Subtask - Define guardrails for max step count and loop-prevention diagnostics.

  [ ] 5.2 Section - Interrupt, Resume, and Cancel Semantics
    Implement deterministic control-flow semantics for interruption and continuation.

    [ ] 5.2.1 Task - Implement interruption control intents
      Translate control signals into consistent run/step state transitions.

      [ ] 5.2.1.1 Subtask - Define interrupt behavior for in-flight strategy execution steps.
      [ ] 5.2.1.2 Subtask - Define interrupt behavior for in-flight tool/command/workflow execution steps.
      [ ] 5.2.1.3 Subtask - Define interruption reason and cause-link propagation rules.

    [ ] 5.2.2 Task - Implement resume and cancel policies
      Allow deterministic continuation or terminalization after interruptions.

      [ ] 5.2.2.1 Subtask - Define resume preconditions and invalid-resume rejection taxonomy.
      [ ] 5.2.2.2 Subtask - Define cancel terminalization semantics for active and idle runs.
      [ ] 5.2.2.3 Subtask - Define resumed-step replay boundaries and idempotency rules.

  [ ] 5.3 Section - Initial Mode Pipeline Definitions
    Define mode-specific pipeline templates using shared step primitives.

    [ ] 5.3.1 Task - Implement coding mode baseline pipeline
      Model coding as a strategy/tool iterative loop with deterministic completion criteria.

      [ ] 5.3.1.1 Subtask - Define coding start step and `execution_kind=:strategy_run` step chain.
      [ ] 5.3.1.2 Subtask - Define tool-request handling and strategy follow-up step insertion.
      [ ] 5.3.1.3 Subtask - Define coding completion and failure terminal conditions.

    [ ] 5.3.2 Task - Implement planning and engineering baseline templates
      Introduce structured templates that can evolve independently of substrate contracts.

      [ ] 5.3.2.1 Subtask - Define planning template steps for structured artifact generation.
      [ ] 5.3.2.2 Subtask - Define engineering template steps for alternative/tradeoff analysis.
      [ ] 5.3.2.3 Subtask - Define shared template extension points and versioning tags.

  [ ] 5.4 Section - Phase 5 Integration Tests
    Validate deterministic pipeline step execution and control semantics under real orchestration flows.

    [ ] 5.4.1 Task - Pipeline planning and execution integration scenarios
      Prove reducer planning and instruction execution stay coherent across step transitions.

      [ ] 5.4.1.1 Subtask - Verify start/continue/terminal step transitions for each mode template.
      [ ] 5.4.1.2 Subtask - Verify tool-request loop insertion and follow-up strategy execution through `Project.ExecutionRunner`.
      [ ] 5.4.1.3 Subtask - Verify deterministic outcomes with repeated/reordered signal ingestion.

    [ ] 5.4.2 Task - Interrupt/resume/cancel integration scenarios
      Prove interruption controls and recovery semantics are deterministic and replay-safe.

      [ ] 5.4.2.1 Subtask - Verify interruption of in-flight strategy and tool steps.
      [ ] 5.4.2.2 Subtask - Verify resume precondition enforcement and successful continuation.
      [ ] 5.4.2.3 Subtask - Verify cancel terminalization and canonical event emission parity.
