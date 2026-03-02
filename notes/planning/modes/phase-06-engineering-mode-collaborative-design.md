# Phase 6 - Tool/Strategy Loop Unification and Cancellation Semantics

Back to index: [README](./README.md)

## Relevant Shared APIs / Interfaces
- `Jido.Code.Server.Conversation.ExecutionBridge` (new, or expansion of `ToolBridge`)
- `Jido.Code.Server.Project.ExecutionRunner`
- `Jido.Code.Server.Project.StrategyRunner` (new)
- `Jido.Code.Server.Project.ToolRunner`
- `Jido.Code.Server.Project.CommandRunner`
- `Jido.Code.Server.Project.WorkflowRunner`
- `Jido.Code.Server.Conversation.Instructions.RunExecutionInstruction` (new)
- `Jido.Code.Server.Conversation.Actions.Cancel*` flows

## Relevant Assumptions / Defaults
- Tool and strategy calls are orchestrated through unified execution directives.
- `Project.ExecutionRunner` is the only policy enforcement gateway for execution side effects.
- Async tool execution and strategy execution must share cancellation semantics.
- Canonical terminal states must be observable in `conversation.*` and `conv.*`.

[x] 6 Phase 6 - Tool/Strategy Loop Unification and Cancellation Semantics
  Unify the strategy and tool execution loop so cancellation, timeout, and failure behavior are coherent and deterministic.

  [x] 6.1 Section - Unified Execution Envelope and Lifecycle Vocabulary
    Normalize execution metadata and lifecycle status across strategy and tool paths.

    [x] 6.1.1 Task - Define shared execution envelope
      Use one metadata shape for identity, causality, and observability across execution types.

      [x] 6.1.1.1 Subtask - Define shared fields (`execution_id`, `correlation_id`, `cause_id`, `step_id`, `run_id`, `mode`).
      [x] 6.1.1.2 Subtask - Define shared lifecycle statuses (`requested`, `started`, `progress`, `completed`, `failed`, `canceled`).
      [x] 6.1.1.3 Subtask - Define mapping rules from runner/adapter-native statuses to shared vocabulary.

    [x] 6.1.2 Task - Align event emission paths
      Ensure both execution types emit consistent orchestration events and bridge cleanly to canonical streams.

      [x] 6.1.2.1 Subtask - Align tool and strategy event payload shapes for status and errors.
      [x] 6.1.2.2 Subtask - Align terminal event requirements and completion semantics.
      [x] 6.1.2.3 Subtask - Align `JournalBridge` mapping for unified lifecycle payloads.

  [x] 6.2 Section - Cancellation, Timeout, and Recovery Semantics
    Make all interruption paths explicit, deterministic, and resumable where policy allows.

    [x] 6.2.1 Task - Unify cancellation orchestration
      Cancel active strategy and tool executions through one reducer/control flow.

      [x] 6.2.1.1 Subtask - Define cancellation intent precedence for active run, active step, and pending queue.
      [x] 6.2.1.2 Subtask - Wire cancellation to strategy adapter cancel callbacks through delegated strategy runner path.
      [x] 6.2.1.3 Subtask - Wire cancellation to `ExecutionRunner.cancel_task/3` and pending-task cleanup across delegated sub-runners.

    [x] 6.2.2 Task - Standardize timeout and retry behavior
      Apply consistent timeout/retry semantics with explicit terminalization behavior.

      [x] 6.2.2.1 Subtask - Define timeout categories and retryability mapping for tool and strategy paths.
      [x] 6.2.2.2 Subtask - Define max-attempt and backoff policy integration with step state.
      [x] 6.2.2.3 Subtask - Define failure escalation and non-retryable terminalization rules.

  [x] 6.3 Section - Policy, Safety, and Resource Governance
    Ensure unified loop respects project policy and operational safeguards.

    [x] 6.3.1 Task - Enforce policy across all execution kinds
      Ensure no strategy/tool/command/workflow execution can bypass policy and safety constraints.

      [x] 6.3.1.1 Subtask - Validate strategy-emitted executions through unified execution-call normalization.
      [x] 6.3.1.2 Subtask - Apply `ExecutionRunner` policy checks consistently for strategy/tool/command/workflow execution kinds.
      [x] 6.3.1.3 Subtask - Emit policy decision records with correlation to originating strategy step.

    [x] 6.3.2 Task - Enforce concurrency and output limits
      Keep execution stable under load and prevent unbounded output growth.

      [x] 6.3.2.1 Subtask - Define per-conversation limits for concurrent strategy/tool executions.
      [x] 6.3.2.2 Subtask - Define max output/token/artifact thresholds and truncation behavior.
      [x] 6.3.2.3 Subtask - Define degraded-mode behavior when limits are exceeded.

  [x] 6.4 Section - Phase 6 Integration Tests
    Validate unified loop semantics for cancellation, timeout, and policy under mixed tool/strategy flows.

    [x] 6.4.1 Task - Unified lifecycle integration scenarios
      Prove tool and strategy paths emit consistent lifecycle behavior under normal and failure conditions.

      [x] 6.4.1.1 Subtask - Verify lifecycle status parity for sync and async tool paths.
      [x] 6.4.1.2 Subtask - Verify lifecycle status parity for streaming and non-streaming strategy paths.
      [x] 6.4.1.3 Subtask - Verify terminal status parity and metadata across bridge-to-canonical mapping.

    [x] 6.4.2 Task - Cancellation and governance integration scenarios
      Prove cancellation and policy safeguards hold under concurrent, mixed workloads.

      [x] 6.4.2.1 Subtask - Verify cancel of active tool and active strategy with deterministic terminal events.
      [x] 6.4.2.2 Subtask - Verify timeout/retry policies and terminalization after exhaustion.
      [x] 6.4.2.3 Subtask - Verify policy denial and resource-limit enforcement with full audit trails.
