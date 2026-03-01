# Phase 2 - Mode Registry, Configuration, and Switching

Back to index: [README](./README.md)

## Relevant Shared APIs / Interfaces
- `Jido.Conversation.Mode.Registry`
- `JidoConversation.supported_modes/0`
- `JidoConversation.configure_mode/3`
- Mode option resolution and validation helpers

## Relevant Assumptions / Defaults
- Registry may be seeded from defaults and app/runtime configuration.
- Configuration precedence is deterministic.
- Mode switching defaults to safe behavior (reject if active run exists).

[ ] 2 Phase 2 - Mode Registry, Configuration, and Switching
  Build deterministic mode discovery, validation, and switching behavior with strict transition rules.

  [ ] 2.1 Section - Mode Registry and Discovery
    Define and implement how mode modules are registered and enumerated.

    [ ] 2.1.1 Task - Implement registry source and validation contract
      Ensure registry state is deterministic, valid, and conflict-safe.

      [ ] 2.1.1.1 Subtask - Define source precedence: built-in defaults, app config, runtime overrides.
      [ ] 2.1.1.2 Subtask - Validate mode IDs, module availability, and callback completeness.
      [ ] 2.1.1.3 Subtask - Define duplicate mode ID conflict handling policy.

    [ ] 2.1.2 Task - Implement supported-modes metadata surface
      Expose useful mode metadata for host UX and debugging.

      [ ] 2.1.2.1 Subtask - Define metadata fields: id, summary, capabilities, required options.
      [ ] 2.1.2.2 Subtask - Define stability/version tags for mode modules.
      [ ] 2.1.2.3 Subtask - Define deterministic ordering and filtering behavior.

  [ ] 2.2 Section - Configuration Resolution and Option Schemas
    Resolve effective mode configuration from layered defaults and request-level overrides.

    [ ] 2.2.1 Task - Implement mode config resolver
      Merge options with explicit precedence and strict normalization.

      [ ] 2.2.1.1 Subtask - Define precedence: request > conversation > mode defaults > app defaults.
      [ ] 2.2.1.2 Subtask - Normalize option values and types.
      [ ] 2.2.1.3 Subtask - Produce structured, path-aware validation diagnostics.

    [ ] 2.2.2 Task - Implement per-mode option schema validation
      Enforce required and optional settings by mode.

      [ ] 2.2.2.1 Subtask - Define required options for `:planning` and `:engineering`.
      [ ] 2.2.2.2 Subtask - Define allowed unknown-key policy.
      [ ] 2.2.2.3 Subtask - Define mode-specific defaulting semantics.

  [ ] 2.3 Section - Mode Switching Semantics and Auditability
    Make mode transitions predictable and fully traceable in runtime events.

    [ ] 2.3.1 Task - Implement safe switching rules
      Ensure mode changes preserve run integrity and deterministic behavior.

      [ ] 2.3.1.1 Subtask - Allow mode switches when conversation is idle.
      [ ] 2.3.1.2 Subtask - Reject mode switches during active runs by default.
      [ ] 2.3.1.3 Subtask - Define forced-switch flow with explicit cancel reason requirements.

    [ ] 2.3.2 Task - Implement switch event emission and trace linkage
      Emit clear acceptance/rejection events and ensure cause chains are preserved.

      [ ] 2.3.2.1 Subtask - Emit switch accepted and switch rejected lifecycle events.
      [ ] 2.3.2.2 Subtask - Include previous mode, next mode, and reason metadata.
      [ ] 2.3.2.3 Subtask - Link transition events to causal control/input events.

  [ ] 2.4 Section - Phase 2 Integration Tests
    Validate registry, configuration precedence, and switching rules end-to-end.

    [ ] 2.4.1 Task - Registry and resolver integration scenarios
      Verify deterministic mode registration and effective option resolution.

      [ ] 2.4.1.1 Subtask - Verify expected supported-mode listing and ordering.
      [ ] 2.4.1.2 Subtask - Verify option precedence and normalization outcomes.
      [ ] 2.4.1.3 Subtask - Verify failure behavior on invalid mode configuration.

    [ ] 2.4.2 Task - Switching-policy integration scenarios
      Verify mode switching behavior under idle and active execution states.

      [ ] 2.4.2.1 Subtask - Verify successful idle switches.
      [ ] 2.4.2.2 Subtask - Verify active-run switch rejection.
      [ ] 2.4.2.3 Subtask - Verify forced switch cancellation and transition event sequence.
