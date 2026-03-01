# Conversation Modes Cross-Repo Planning Index

This directory contains the phased implementation plan for moving conversation mode business logic out of `jido_conversation` and into `jido_code_server`, while keeping `jido_conversation` focused on canonical interruptible event ingestion, replay, and projections.

This plan supersedes the previous in-library modes plan.

## Phase Files
1. [Phase 1 - Ownership Boundaries and Contract Reset](./phase-01-foundation-and-mode-contracts.md): redefine cross-repo ownership and lock canonical contracts.
2. [Phase 2 - Canonical Event Substrate Hardening (`jido_conversation`)](./phase-02-mode-registry-configuration-and-switching.md): simplify and harden `jido_conversation` as event substrate only.
3. [Phase 3 - Mode Orchestration Runtime Foundation (`jido_code_server`)](./phase-03-interruptible-pipeline-runtime.md): establish mode-aware state and deterministic orchestration in code server.
4. [Phase 4 - Strategy Execution Layer and Adapter Contracts](./phase-04-coding-mode-parity-migration.md): introduce strategy instruction/adapters for `JidoAI` strategy types and runtime selection.
5. [Phase 5 - Pipeline Step Engine and Interruptibility](./phase-05-planning-mode-implementation.md): implement mode pipelines as interruptible reducer-driven steps in code server.
6. [Phase 6 - Tool/Strategy Loop Unification and Cancellation Semantics](./phase-06-engineering-mode-collaborative-design.md): unify strategy and tool execution loop with robust cancellation and recovery.
7. [Phase 7 - Migration Cutover and Removal of In-Library Mode Business Logic](./phase-07-cross-mode-recovery-and-determinism.md): remove or freeze mode business logic from `jido_conversation` and complete cutover.
8. [Phase 8 - Cross-Repo Integration, Documentation, and Release Readiness](./phase-08-observability-docs-release-and-extension-model.md): finalize integration gates, docs, and release criteria.

## Shared Conventions
- Numbering:
  - Phases: `N`
  - Sections: `N.M`
  - Tasks: `N.M.K`
  - Subtasks: `N.M.K.L`
- Tracking:
  - Every phase, section, task, and subtask uses Markdown checkboxes (`[ ]`).
- Description requirement:
  - Every phase, section, and task begins with a short unlabeled description paragraph.
- Integration-test requirement:
  - Each phase ends with a final integration-testing section.

## Shared API / Interface Contract (Target State)
- `jido_conversation`:
  - canonical `conv.*` contract normalization and ingestion (`Ingest.Pipeline`, adapters)
  - replay, trace, and read models (timeline, llm_context)
  - no mode-specific business orchestration
- `jido_code_server`:
  - conversation orchestration domain (`conversation.*`)
  - mode switching, mode state, run lifecycle, strategy selection
  - tool declaration and inventory ownership (`ToolCatalog` backed by action-based providers, not raw project markdown assets)
  - single execution gateway (`Project.ExecutionRunner`) for strategy, tool, command, and workflow effects
  - instruction-based side effects routed through unified execution directives
  - bridging `conversation.*` to `conv.*` via `JournalBridge`

## Shared Assumptions and Defaults
- `jido_code_server` is the orchestration host; `jido_conversation` is the canonical event substrate.
- Mode pipelines execute as reducer-derived intents in `jido_code_server`.
- `JidoAI` strategy type selection is owned by mode runtime/config in `jido_code_server`.
- LLM-visible tool inventory and tool exposure policy are owned by `jido_code_server`, using action-compatible tool definitions aligned with `jido_ai`.
- `.jido` markdown content is a runtime input concern of provider libraries (`jido_command`, `jido_workflow`, `jido_skill`), not the direct source of LLM tool declarations.
- All execution paths are policy-gated through `Project.ExecutionRunner`, which delegates by call kind to specialized sub-runners (including strategy/tool/command/workflow).
- Interrupt/cancel semantics are deterministic and recorded through append-only events.

## Cross-Phase Acceptance Scenarios
- [ ] XR-1 A full user -> strategy -> tool -> strategy loop is orchestrated in `jido_code_server` and represented in canonical `conv.*` streams.
- [ ] XR-2 `jido_conversation` can be replayed independently and reconstruct equivalent read models without embedded mode business logic.
- [ ] XR-3 Mode switching, interruption, resume, and cancellation are deterministic and recoverable across process restarts.
- [ ] XR-4 Multiple strategy types can be selected per mode without changing substrate contracts.
- [ ] XR-5 Tool and strategy cancellation behavior produces consistent terminal events and cause-link metadata.
- [ ] XR-6 Legacy host entry points continue to work through explicit orchestration adapters during migration.
- [ ] XR-7 Cross-repo CI validates contract compatibility and detects drift before merge.
- [ ] XR-8 Developer and user docs clearly reflect the new ownership model and extension points.
- [ ] XR-9 Every mode step requiring side effects is routed through `Project.ExecutionRunner` with auditable policy decisions.
- [ ] XR-10 Only action-backed tools registered through `jido_code_server` providers are surfaced to LLM execution for conversation runs.
