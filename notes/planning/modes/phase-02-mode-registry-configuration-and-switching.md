# Phase 2 - Canonical Event Substrate Hardening (`jido_conversation`)

Back to index: [README](./README.md)

## Relevant Shared APIs / Interfaces
- `JidoConversation.Signal.Contract`
- `JidoConversation.Ingest.Pipeline`
- `JidoConversation.Ingest.Adapters.*`
- `JidoConversation.Projections.Timeline`
- `JidoConversation.Projections.LlmContext`

## Relevant Assumptions / Defaults
- `jido_conversation` should not own mode/business policy execution.
- Host orchestration still depends on stable `conv.*` semantics.
- Replay determinism remains a hard non-negotiable.

[x] 2 Phase 2 - Canonical Event Substrate Hardening (`jido_conversation`)
  Refactor and harden `jido_conversation` to serve as a pure interruptible event substrate for external orchestrators.

  [x] 2.1 Section - Remove or Isolate In-Library Mode Business Paths
    Eliminate mode pipeline ownership from substrate runtime while preserving canonical event integrity.

    [x] 2.1.1 Task - Define minimal public responsibility surface
      Trim or freeze APIs that imply orchestration ownership and keep substrate responsibilities explicit.

      [x] 2.1.1.1 Subtask - Classify current mode-related APIs as substrate-safe, host-only, or removable.
      [x] 2.1.1.2 Subtask - Remove or deprecate in-library pipeline entry points that execute business logic.
      [x] 2.1.1.3 Subtask - Ensure remaining APIs are strictly ingest/query/replay/health oriented.

    [x] 2.1.2 Task - Isolate any remaining compatibility shims
      Keep transition shims deterministic and auditable if temporarily required.

      [x] 2.1.2.1 Subtask - Route shim behavior to canonical ingest paths, never direct orchestration.
      [x] 2.1.2.2 Subtask - Emit audit markers identifying shim-originated behavior.
      [x] 2.1.2.3 Subtask - Define explicit removal criteria for each shim.

  [x] 2.2 Section - Strengthen Host-Orchestrated Ingest Contracts
    Ensure `jido_code_server` can publish rich orchestration outcomes without substrate ambiguity.

    [x] 2.2.1 Task - Harden adapter coverage for orchestration lifecycles
      Expand or normalize adapters to represent strategy/tool/interruption lifecycles cleanly.

      [x] 2.2.1.1 Subtask - Validate outbound adapters for assistant/tool status parity (`delta`, `completed`, `failed`, `canceled`).
      [x] 2.2.1.2 Subtask - Validate control adapters for interrupt/stop/cancel causality.
      [x] 2.2.1.3 Subtask - Define canonical audit event payloads for host decision records.

    [x] 2.2.2 Task - Enforce stricter contract validation diagnostics
      Make contract failures actionable during cross-repo integration.

      [x] 2.2.2.1 Subtask - Add field-path diagnostics for missing/invalid bridge payload fields.
      [x] 2.2.2.2 Subtask - Add namespace diagnostics for unexpected `conversation.*` leakage into substrate.
      [x] 2.2.2.3 Subtask - Add contract-version mismatch diagnostics with remediation hints.

  [x] 2.3 Section - Projection and Replay Invariants
    Guarantee read models remain stable with orchestration logic moved out of library core.

    [x] 2.3.1 Task - Stabilize projection behavior for host-originated events
      Preserve timeline and llm_context fidelity regardless of upstream orchestration strategy.

      [x] 2.3.1.1 Subtask - Define projection treatment for tool status variants and strategy-generated assistant chunks.
      [x] 2.3.1.2 Subtask - Define llm_context inclusion policy for execution outputs and cancellations across strategy/tool paths.
      [x] 2.3.1.3 Subtask - Define projection metadata retention boundaries to prevent unbounded payload growth.

    [x] 2.3.2 Task - Harden replay determinism and traceability
      Keep replay parity robust as orchestration event richness grows.

      [x] 2.3.2.1 Subtask - Verify replay reconstruction parity for representative orchestration traces.
      [x] 2.3.2.2 Subtask - Verify cause-chain traversal across mixed inbound/outbound/effect streams.
      [x] 2.3.2.3 Subtask - Verify dedupe semantics remain stable under repeated bridged events.

  [x] 2.4 Section - Phase 2 Integration Tests
    Validate substrate-only responsibilities, adapter contracts, and replay invariants end-to-end.

    [x] 2.4.1 Task - Host-ingest contract integration scenarios
      Prove `jido_code_server`-shaped payloads are accepted and projected consistently.

      [x] 2.4.1.1 Subtask - Verify bridged user/assistant/tool flows ingest into canonical streams successfully.
      [x] 2.4.1.2 Subtask - Verify invalid bridge payloads fail with deterministic diagnostics.
      [x] 2.4.1.3 Subtask - Verify cancellation and interruption lifecycles project as expected.

    [x] 2.4.2 Task - Replay and projection integration scenarios
      Prove deterministic reconstruction from canonical logs after orchestration separation.

      [x] 2.4.2.1 Subtask - Verify timeline parity between live and replay paths.
      [x] 2.4.2.2 Subtask - Verify llm_context parity between live and replay paths.
      [x] 2.4.2.3 Subtask - Verify cause-chain and audit trace continuity.
