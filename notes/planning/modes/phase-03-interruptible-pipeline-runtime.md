# Phase 3 - Mode Orchestration Runtime Foundation (`jido_code_server`)

Back to index: [README](./README.md)

## Relevant Shared APIs / Interfaces
- `Jido.Code.Server.Conversation.Domain.State`
- `Jido.Code.Server.Conversation.Domain.Reducer`
- `Jido.Code.Server.Conversation.Actions.Support`
- `Jido.Code.Server.Project.ExecutionRunner`
- `Jido.Code.Server.Project.Server` conversation orchestration toggles

## Relevant Assumptions / Defaults
- Mode runtime source-of-truth lives in `jido_code_server` domain state.
- Reducer remains pure and emits intents/directives.
- Mode-aware orchestration builds on existing instruction execution flow.
- Reducer-generated execution intents are normalized to one execution call shape handled by `Project.ExecutionRunner`.

[ ] 3 Phase 3 - Mode Orchestration Runtime Foundation (`jido_code_server`)
  Establish the mode-aware conversation orchestration core in code server with deterministic state, transitions, and event production.

  [ ] 3.1 Section - Mode-Aware Domain State Model
    Extend conversation domain state to represent mode lifecycle and run tracking as first-class orchestration state.

    [ ] 3.1.1 Task - Add mode state fields and invariants
      Introduce normalized state shape for mode runtime without side effects.

      [ ] 3.1.1.1 Subtask - Add fields (`mode`, `mode_state`, `active_run`, `run_history`, `pending_steps`).
      [ ] 3.1.1.2 Subtask - Define allowed run statuses and transition matrix.
      [ ] 3.1.1.3 Subtask - Define bounded history retention and serialization rules.

    [ ] 3.1.2 Task - Add projections and diagnostics for mode runtime
      Expose mode/run visibility for host APIs and debugging.

      [ ] 3.1.2.1 Subtask - Extend diagnostics projection with mode and run snapshots.
      [ ] 3.1.2.2 Subtask - Add pending-step and interruption metadata to domain projections.
      [ ] 3.1.2.3 Subtask - Define redaction policy for strategy/tool payload fragments in diagnostics.

  [ ] 3.2 Section - Mode Registry and Configuration in Code Server
    Move mode discovery and config precedence to host orchestration where business policy belongs.

    [ ] 3.2.1 Task - Implement code-server mode registry contract
      Provide deterministic mode metadata and capability discovery at orchestration layer.

      [ ] 3.2.1.1 Subtask - Define built-in modes (`:coding`, `:planning`, `:engineering`) with metadata.
      [ ] 3.2.1.2 Subtask - Define registry extension path for custom modes.
      [ ] 3.2.1.3 Subtask - Define mode capability contract (strategy support, tool policy, interruption semantics).

    [ ] 3.2.2 Task - Implement mode config resolver
      Resolve effective mode config with deterministic precedence and validation.

      [ ] 3.2.2.1 Subtask - Define precedence (request > conversation > project/runtime defaults > mode defaults).
      [ ] 3.2.2.2 Subtask - Validate required mode options and unknown-key policy.
      [ ] 3.2.2.3 Subtask - Emit structured diagnostics for invalid configuration.

    [ ] 3.2.3 Task - Define unified mode-to-execution mapping contract
      Ensure all mode step effects map to one execution envelope consumed by `Project.ExecutionRunner`.

      [ ] 3.2.3.1 Subtask - Define normalized execution envelope fields (`execution_kind`, `name`, `args`, `meta`, `correlation_id`, `cause_id`).
      [ ] 3.2.3.2 Subtask - Define deterministic mapping from mode step intents to execution kinds (`strategy_run`, tool kinds, `command_run`, `workflow_run`).
      [ ] 3.2.3.3 Subtask - Define rejection behavior when an intent cannot be mapped to a supported execution kind.

  [ ] 3.3 Section - Mode Switching and Run Lifecycle Control
    Implement switching semantics and lifecycle events as reducer-driven orchestration behavior.

    [ ] 3.3.1 Task - Implement safe mode switch policy
      Ensure switching behavior preserves deterministic run and cancellation semantics.

      [ ] 3.3.1.1 Subtask - Allow switch while idle and reject conflicting active-run switches by default.
      [ ] 3.3.1.2 Subtask - Define forced-switch policy with explicit interruption/cancel reason.
      [ ] 3.3.1.3 Subtask - Define state reset/retention behavior when switching modes.

    [ ] 3.3.2 Task - Emit mode lifecycle orchestration events
      Produce consistent `conversation.*` signals for switch acceptance/rejection and run lifecycle changes.

      [ ] 3.3.2.1 Subtask - Emit switch accepted/rejected events with cause metadata.
      [ ] 3.3.2.2 Subtask - Emit run opened/interrupted/resumed/closed events.
      [ ] 3.3.2.3 Subtask - Ensure events flow through `JournalBridge` into canonical `conv.*` streams.

  [ ] 3.4 Section - Phase 3 Integration Tests
    Validate mode state, registry resolution, and switching lifecycle under orchestration runtime.

    [ ] 3.4.1 Task - Mode state and config integration scenarios
      Prove mode registration and config resolution are deterministic and observable.

      [ ] 3.4.1.1 Subtask - Verify supported-mode listing and metadata surface.
      [ ] 3.4.1.2 Subtask - Verify resolver precedence and validation failures.
      [ ] 3.4.1.3 Subtask - Verify diagnostics projection contains normalized mode/run fields.
      [ ] 3.4.1.4 Subtask - Verify mode-step intents resolve to supported unified execution envelope values.

    [ ] 3.4.2 Task - Switch and lifecycle integration scenarios
      Prove switching and run state transitions hold under real conversation traffic.

      [ ] 3.4.2.1 Subtask - Verify idle switch success and active-run rejection path.
      [ ] 3.4.2.2 Subtask - Verify forced-switch interruption path with explicit reason.
      [ ] 3.4.2.3 Subtask - Verify bridged canonical events preserve switch/run causality.
