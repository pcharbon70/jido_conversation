# Phase 7 - Migration Cutover and Removal of In-Library Mode Business Logic

Back to index: [README](./README.md)

## Relevant Shared APIs / Interfaces
- `JidoConversation` public facade
- `Jido.Conversation.*` mode-related modules (current implementation)
- `Jido.Code.Server` conversation orchestration APIs
- `Jido.Code.Server.Conversation.JournalBridge`

## Relevant Assumptions / Defaults
- Backward compatibility is not required.
- Final orchestration owner is `jido_code_server`.
- `jido_conversation` must remain stable as canonical event substrate.

[x] 7 Phase 7 - Migration Cutover and Removal of In-Library Mode Business Logic
  Complete migration by cutting orchestration ownership to code server and removing in-library mode business paths from `jido_conversation`.

  [x] 7.1 Section - Cutover Execution and Runtime Path Switch
    Perform deterministic runtime switch to code-server-owned mode orchestration.

    [x] 7.1.1 Task - Enable code-server mode orchestration as default path
      Make code-server pipeline runtime authoritative for all mode behavior.

      [x] 7.1.1.1 Subtask - Set runtime defaults to code-server mode orchestration path.
      [x] 7.1.1.2 Subtask - Remove fallback routing to in-library mode execution.
      [x] 7.1.1.3 Subtask - Add startup-time contract checks to fail fast on path mismatch.

    [x] 7.1.2 Task - Verify host API routing and call-path integrity
      Ensure host APIs route through orchestration runtime and canonical bridge as expected.

      [x] 7.1.2.1 Subtask - Validate conversation call/cast paths trigger reducer-intent orchestration.
      [x] 7.1.2.2 Subtask - Validate async tool result re-ingestion continues to work post-cutover.
      [x] 7.1.2.3 Subtask - Validate canonical `conv.*` events still represent full user-visible lifecycle.

  [x] 7.2 Section - Remove Mode Business Logic from `jido_conversation`
    Reduce `jido_conversation` code surface to substrate-only responsibilities.

    [x] 7.2.1 Task - Remove superseded mode runtime modules
      Eliminate modules and flows that execute mode business logic directly in library runtime.

      [x] 7.2.1.1 Subtask - Remove/retire `Jido.Conversation.Mode*` business orchestration modules.
      [x] 7.2.1.2 Subtask - Remove/retire mode-run state transitions from in-library runtime/server paths.
      [x] 7.2.1.3 Subtask - Remove stale tests and fixtures tied to removed in-library orchestration.

    [x] 7.2.2 Task - Keep substrate APIs clean and explicit
      Preserve only canonical event and projection responsibilities with clear documentation.

      [x] 7.2.2.1 Subtask - Update public API docs to describe substrate-only purpose.
      [x] 7.2.2.2 Subtask - Update telemetry/health docs to remove orchestration claims.
      [x] 7.2.2.3 Subtask - Add explicit references to host orchestration responsibilities.

  [x] 7.3 Section - Cross-Repo Contract and Test Suite Realignment
    Align tests and contracts to the new architecture where code server owns business behavior.

    [x] 7.3.1 Task - Rework test ownership boundaries
      Move tests to the repository that owns each behavior to reduce cross-layer ambiguity.

      [x] 7.3.1.1 Subtask - Keep canonical contract/replay tests in `jido_conversation`.
      [x] 7.3.1.2 Subtask - Move mode pipeline and strategy tests to `jido_code_server`.
      [x] 7.3.1.3 Subtask - Add shared fixtures for `conversation.*` -> `conv.*` mapping parity.

    [x] 7.3.2 Task - Remove obsolete migration scaffolding
      Clean transitional flags, adapters, and compatibility shims after successful cutover.

      [x] 7.3.2.1 Subtask - Remove migration-only flags and dead-path toggles.
      [x] 7.3.2.2 Subtask - Remove legacy compatibility wrappers and docs.
      [x] 7.3.2.3 Subtask - Confirm no dead code remains via static analysis and coverage.

  [x] 7.4 Section - Phase 7 Integration Tests
    Validate final cutover architecture with no in-library mode business runtime remaining.

    [x] 7.4.1 Task - Architecture ownership integration scenarios
      Prove runtime behavior follows new ownership boundaries in all core flows.

      [x] 7.4.1.1 Subtask - Verify mode execution only occurs in `jido_code_server`.
      [x] 7.4.1.2 Subtask - Verify `jido_conversation` remains fully functional for ingest/replay/projections.
      [x] 7.4.1.3 Subtask - Verify bridge parity for full tool/strategy loop traces.

    [x] 7.4.2 Task - Cleanup and regression integration scenarios
      Prove removed paths do not regress core canonical behavior.

      [x] 7.4.2.1 Subtask - Verify no references to removed mode business modules remain in runtime paths.
      [x] 7.4.2.2 Subtask - Verify canonical contract and projection tests pass after cleanup.
      [x] 7.4.2.3 Subtask - Verify deterministic replay parity for migrated orchestration traces.
