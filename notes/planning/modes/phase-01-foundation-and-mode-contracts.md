# Phase 1 - Foundation and Mode Contracts

Back to index: [README](./README.md)

## Relevant Shared APIs / Interfaces
- `Jido.Conversation.Mode`
- `JidoConversation.configure_mode/3`
- `JidoConversation.mode/1`
- `JidoConversation.supported_modes/0`
- Conversation state and projection contracts

## Relevant Assumptions / Defaults
- Default mode is `:coding`.
- Mode contracts are additive and do not remove existing APIs.
- Mode lifecycle must be replay-safe through journal entries/signals.

[ ] 1 Phase 1 - Foundation and Mode Contracts
  Establish foundational abstractions, ownership boundaries, and state/event contracts before implementing mode logic.

  [ ] 1.1 Section - Namespace and Ownership Baseline
    Define module boundaries so mode orchestration responsibilities are explicit and maintainable.

    [ ] 1.1.1 Task - Define mode domain module boundaries
      Separate mode interfaces, mode implementations, and runtime execution concerns.

      [ ] 1.1.1.1 Subtask - Introduce namespace map for `Jido.Conversation.Mode*` modules.
      [ ] 1.1.1.2 Subtask - Define ownership of mode orchestration between conversation runtime, server, and reducer layers.
      [ ] 1.1.1.3 Subtask - Document forbidden cross-layer dependencies and access patterns.

    [ ] 1.1.2 Task - Define mode behavior contract
      Establish a complete callback protocol that future modes must implement.

      [ ] 1.1.2.1 Subtask - Define callbacks for init, step planning, effect-event handling, and terminalization.
      [ ] 1.1.2.2 Subtask - Define callbacks for interruption and resume handling.
      [ ] 1.1.2.3 Subtask - Define callback return envelopes for directives, run-state updates, and errors.

  [ ] 1.2 Section - Conversation State and Journal Contract
    Extend conversation state and event contracts to represent mode run lifecycle deterministically.

    [ ] 1.2.1 Task - Define mode-aware conversation state shape
      Add required fields and transition rules for mode execution state.

      [ ] 1.2.1.1 Subtask - Add state fields: `mode`, `mode_state`, `active_run`, and `run_history`.
      [ ] 1.2.1.2 Subtask - Define allowed run statuses and transition matrix.
      [ ] 1.2.1.3 Subtask - Define projection-facing serialization format for run snapshots.

    [ ] 1.2.2 Task - Define mode lifecycle signal and journal schema
      Guarantee that all mode state changes are represented in append-only, replayable events.

      [ ] 1.2.2.1 Subtask - Define `conv.in.mode.*`, `conv.out.mode.*`, and control-event payload contracts.
      [ ] 1.2.2.2 Subtask - Define required lifecycle fields (`mode`, `run_id`, `step_id`, `status`, `reason`).
      [ ] 1.2.2.3 Subtask - Define cause-link and contract-versioning requirements.

  [ ] 1.3 Section - Public API and Error Taxonomy Baseline
    Lock external contracts early so downstream phases can implement without ambiguity.

    [ ] 1.3.1 Task - Define public mode API signatures and semantics
      Specify exact arguments, return tuples, and default behavior for mode management.

      [ ] 1.3.1.1 Subtask - Define `configure_mode/3` contract and validation flow.
      [ ] 1.3.1.2 Subtask - Define `mode/1` and `supported_modes/0` contract shapes.
      [ ] 1.3.1.3 Subtask - Define expected delegation boundaries for legacy APIs.

    [ ] 1.3.2 Task - Define mode error taxonomy
      Normalize host-facing failure outcomes for predictable handling.

      [ ] 1.3.2.1 Subtask - Define errors for unsupported modes and invalid transitions.
      [ ] 1.3.2.2 Subtask - Define run-state errors (`:run_in_progress`, `:run_not_found`, `:resume_not_allowed`).
      [ ] 1.3.2.3 Subtask - Define structured error metadata fields for telemetry and projections.

  [ ] 1.4 Section - Phase 1 Integration Tests
    Validate foundational contracts and replay-safe state representation before runtime changes.

    [ ] 1.4.1 Task - API and state contract integration scenarios
      Prove mode metadata and baseline state interfaces behave as specified.

      [ ] 1.4.1.1 Subtask - Verify default mode initialization.
      [ ] 1.4.1.2 Subtask - Verify unsupported mode rejection.
      [ ] 1.4.1.3 Subtask - Verify mode fields appear in derived state and projections.

    [ ] 1.4.2 Task - Signal and taxonomy integration scenarios
      Prove contract enforcement and normalized error mapping across boundaries.

      [ ] 1.4.2.1 Subtask - Validate mode signal payload schemas via contract normalization.
      [ ] 1.4.2.2 Subtask - Validate error taxonomy mapping on invalid requests.
      [ ] 1.4.2.3 Subtask - Validate cause-link metadata propagation in foundational events.
