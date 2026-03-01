# Phase 4 - Strategy Execution Layer and Adapter Contracts

Back to index: [README](./README.md)

## Relevant Shared APIs / Interfaces
- `Jido.Code.Server.Conversation.Instructions.RunExecutionInstruction` (new)
- `Jido.Code.Server.Project.ExecutionRunner`
- `Jido.Code.Server.Project.StrategyRunner` (new)
- `Jido.Code.Server.Conversation.LLM`
- `Jido.Code.Server.Conversation.Actions.Support`
- `Jido.AI` strategy modules and strategy-type contracts

## Relevant Assumptions / Defaults
- Strategy selection is owned by `jido_code_server` mode runtime.
- Strategy execution returns canonical `conversation.*` signals for re-ingestion.
- Strategy and tool calls are policy-gated through `Project.ExecutionRunner` and its delegated sub-runners.

[ ] 4 Phase 4 - Strategy Execution Layer and Adapter Contracts
  Introduce a strategy-centric execution layer so each mode can choose different `JidoAI` strategy types without changing canonical event contracts.

  [ ] 4.1 Section - Unified Strategy Execution Gateway Path
    Route strategy execution through the same execution instruction and gateway used for other side effects.

    [ ] 4.1.1 Task - Define `strategy_run` execution contract
      Standardize execution envelope input/output and failure behavior for strategy calls through `Project.ExecutionRunner`.

      [ ] 4.1.1.1 Subtask - Define params envelope (`mode`, `strategy_type`, `strategy_opts`, `source_signal`, `llm_context`, `execution_kind=:strategy_run`).
      [ ] 4.1.1.2 Subtask - Define normalized success payload shape (`signals`, `result_meta`, `execution_ref`).
      [ ] 4.1.1.3 Subtask - Define normalized error payload shape and retryability hints.

    [ ] 4.1.2 Task - Integrate strategy intent-to-unified-execution mapping
      Connect reducer intents to one execution instruction pathway through existing support layer.

      [ ] 4.1.2.1 Subtask - Add `intent(kind=:run_execution, execution_kind=:strategy_run)` mapping in `Actions.Support`.
      [ ] 4.1.2.2 Subtask - Preserve `HandleInstructionResultAction` ingestion path for returned signals.
      [ ] 4.1.2.3 Subtask - Add execution-kind metadata and telemetry dimensions for strategy executions.

  [ ] 4.2 Section - Strategy Adapter Abstractions and Selection
    Introduce deterministic strategy adapter contracts so modes can swap strategy types safely.

    [ ] 4.2.1 Task - Define `StrategyRunner` adapter behavior
      Normalize strategy-specific implementations behind one delegated execution interface.

      [ ] 4.2.1.1 Subtask - Define callbacks for `start`, optional `stream`, and optional `cancel` semantics.
      [ ] 4.2.1.2 Subtask - Define adapter capability metadata (`streaming?`, `tool_calling?`, `cancellable?`).
      [ ] 4.2.1.3 Subtask - Define adapter registration/validation rules and `ExecutionRunner` delegation contract.

    [ ] 4.2.2 Task - Implement mode-to-strategy selection policy
      Resolve strategy types/options per mode with deterministic precedence.

      [ ] 4.2.2.1 Subtask - Define default strategy type per mode (`:coding`, `:planning`, `:engineering`).
      [ ] 4.2.2.2 Subtask - Define project/runtime overrides and per-request overrides.
      [ ] 4.2.2.3 Subtask - Define rejection behavior for unsupported strategy/mode combinations.

  [ ] 4.3 Section - Strategy Output Normalization and Bridging
    Ensure all strategy outcomes become canonical signals understood by reducer and substrate.

    [ ] 4.3.1 Task - Normalize strategy events to `conversation.*`
      Convert strategy-native responses to deterministic orchestration event stream.

      [ ] 4.3.1.1 Subtask - Emit assistant delta/message lifecycles from strategy chunks/finals.
      [ ] 4.3.1.2 Subtask - Emit tool-requested signals when strategy outputs tool calls.
      [ ] 4.3.1.3 Subtask - Emit terminal strategy completion/failure/cancellation events with cause metadata.

    [ ] 4.3.2 Task - Preserve metadata and observability invariants
      Keep correlation, execution identity, and model/provider metadata stable across adapters.

      [ ] 4.3.2.1 Subtask - Preserve correlation_id and cause_id across all emitted events.
      [ ] 4.3.2.2 Subtask - Preserve strategy/model/provider metadata with normalization rules.
      [ ] 4.3.2.3 Subtask - Emit telemetry for strategy lifecycle, retries, and cancellation outcomes.

  [ ] 4.4 Section - Phase 4 Integration Tests
    Validate strategy instruction execution and adapter normalization end-to-end.

    [ ] 4.4.1 Task - Strategy selection and execution-gateway integration scenarios
      Prove mode-specific strategy selection and routing through the unified gateway path.

      [ ] 4.4.1.1 Subtask - Verify mode default strategy selection behavior.
      [ ] 4.4.1.2 Subtask - Verify override precedence and invalid-combination rejection.
      [ ] 4.4.1.3 Subtask - Verify unified execution-result re-ingestion into reducer pipeline.

    [ ] 4.4.2 Task - Strategy output normalization integration scenarios
      Prove strategy outputs produce deterministic orchestration and canonical substrate events.

      [ ] 4.4.2.1 Subtask - Verify delta/message/tool-request mapping for streaming and non-streaming strategies.
      [ ] 4.4.2.2 Subtask - Verify normalized terminal failure/cancellation mapping.
      [ ] 4.4.2.3 Subtask - Verify bridged `conv.*` parity for representative strategy traces.
