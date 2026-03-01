# Phase 1 - Ownership Boundaries and Contract Reset

Back to index: [README](./README.md)

## Relevant Shared APIs / Interfaces
- `Jido.Code.Server.Conversation.Domain.*`
- `Jido.Code.Server.Conversation.Actions.Support`
- `Jido.Code.Server.Conversation.JournalBridge`
- `Jido.Code.Server.Project.ExecutionRunner`
- `JidoConversation.Signal.Contract`
- `JidoConversation.Ingest.Pipeline`

## Relevant Assumptions / Defaults
- Orchestration responsibility moves to `jido_code_server`.
- `jido_conversation` remains canonical `conv.*` event infrastructure.
- Existing behavior may be changed; backward compatibility is not required.

[ ] 1 Phase 1 - Ownership Boundaries and Contract Reset
  Establish explicit cross-repo ownership, event contracts, and migration guardrails before implementing runtime changes.

  [ ] 1.1 Section - Cross-Repo Ownership Model
    Define exactly which repository owns orchestration decisions versus canonical event substrate responsibilities.

    [ ] 1.1.1 Task - Define source-of-truth ownership boundaries
      Document which components own state transitions, business policy, and event persistence semantics.

      [ ] 1.1.1.1 Subtask - Declare `jido_code_server` as owner of mode runtime, strategy selection, pipeline decisions, and execution policy enforcement via `Project.ExecutionRunner`.
      [ ] 1.1.1.2 Subtask - Declare `jido_code_server` as owner of action-based tool declaration/exposure policy for conversation LLM runs.
      [ ] 1.1.1.3 Subtask - Declare provider runtimes (`jido_command`, `jido_workflow`, `jido_skill`) as owners of markdown-to-runtime loading, not direct LLM tool declaration.
      [ ] 1.1.1.4 Subtask - Declare `jido_conversation` as owner of `conv.*` validation, ingestion, replay, and projections.
      [ ] 1.1.1.5 Subtask - Define forbidden dependencies (no orchestration callbacks in `jido_conversation`; no direct substrate bypass in `jido_code_server`; no raw asset-to-tool declaration path).

    [ ] 1.1.2 Task - Define data-flow direction and trust boundaries
      Lock one-way and two-way integration pathways so orchestration remains deterministic and auditable.

      [ ] 1.1.2.1 Subtask - Define `conversation.*` as code-server internal orchestration stream.
      [ ] 1.1.2.2 Subtask - Define `JournalBridge` as canonical translation point into `conv.*`.
      [ ] 1.1.2.3 Subtask - Define allowed call paths for host API and internal calls through `Project.ExecutionRunner`, plus async execution-result re-ingestion.

  [ ] 1.2 Section - Canonical Signal Taxonomy Alignment
    Establish stable mapping between orchestration events and substrate events before moving business logic.

    [ ] 1.2.1 Task - Define cross-stream mapping matrix
      Normalize every orchestration lifecycle event to canonical stream events and required metadata fields.

      [ ] 1.2.1.1 Subtask - Map user, assistant, tool, llm, control, and audit lifecycles (`conversation.*` -> `conv.*`).
      [ ] 1.2.1.2 Subtask - Define required identity fields (`conversation_id`, `output_id`, `tool_call_id`, `correlation_id`, `cause_id`).
      [ ] 1.2.1.3 Subtask - Define failure and cancellation terminal mappings with stable status vocabulary.

    [ ] 1.2.2 Task - Define contract-version and compatibility policy
      Ensure both repos evolve safely without silent drift in event shape or semantics.

      [ ] 1.2.2.1 Subtask - Pin canonical contract-major expectations and rejection behavior.
      [ ] 1.2.2.2 Subtask - Define additive versus breaking field evolution rules for bridge payloads.
      [ ] 1.2.2.3 Subtask - Define contract drift detection checks in shared test fixtures.

  [ ] 1.3 Section - Migration Control Plane and Cutover Criteria
    Define sequencing, feature gates, and objective cutover gates for a controlled cross-repo migration.

    [ ] 1.3.1 Task - Define cross-repo feature flags and rollout toggles
      Provide deterministic runtime toggles to switch between legacy and new orchestration paths during migration.

      [ ] 1.3.1.1 Subtask - Define code-server flag for mode runtime ownership (`conversation_orchestration` target mode runtime variant).
      [ ] 1.3.1.2 Subtask - Define conversation-substrate flag set for disabling in-library mode orchestration paths.
      [ ] 1.3.1.3 Subtask - Define safe fallback behavior for partial enablement mismatch.

    [ ] 1.3.2 Task - Define phase gate acceptance criteria
      Establish measurable criteria required before enabling the next migration phase.

      [ ] 1.3.2.1 Subtask - Define runtime determinism gate (same inputs -> same canonical outputs).
      [ ] 1.3.2.2 Subtask - Define interruption/cancellation correctness gate.
      [ ] 1.3.2.3 Subtask - Define cross-repo contract parity gate.

  [ ] 1.4 Section - Phase 1 Integration Tests
    Validate ownership boundaries, mapping matrix, and migration gates before implementing runtime refactors.

    [ ] 1.4.1 Task - Ownership and mapping integration scenarios
      Prove events and responsibilities are enforced at runtime boundaries.

      [ ] 1.4.1.1 Subtask - Verify orchestration intents are produced only in `jido_code_server` domain and execution intents route through `Project.ExecutionRunner`.
      [ ] 1.4.1.2 Subtask - Verify canonical `conv.*` writes are produced through bridge/ingest adapters only.
      [ ] 1.4.1.3 Subtask - Verify canonical output projections remain reconstructable from bridged events.

    [ ] 1.4.2 Task - Contract and gating integration scenarios
      Prove contract-version behavior and migration control toggles are deterministic.

      [ ] 1.4.2.1 Subtask - Verify invalid bridge payloads fail contract checks with explicit diagnostics.
      [ ] 1.4.2.2 Subtask - Verify feature-flag combinations produce expected path selection.
      [ ] 1.4.2.3 Subtask - Verify cutover gate checks fail fast on contract drift.
