# Conversation Modes Planning Index

This directory contains the phased implementation plan for introducing multi-mode, interruptible conversation workflows in `jido_conversation`.

## Phase Files
1. [Phase 1 - Foundation and Mode Contracts](./phase-01-foundation-and-mode-contracts.md): establish mode abstractions, ownership boundaries, and baseline state contracts.
2. [Phase 2 - Mode Registry, Configuration, and Switching](./phase-02-mode-registry-configuration-and-switching.md): implement mode discovery, configuration precedence, and switching policies.
3. [Phase 3 - Interruptible Pipeline Runtime](./phase-03-interruptible-pipeline-runtime.md): build the mode-agnostic step/run orchestration runtime over existing effect infrastructure.
4. [Phase 4 - Coding Mode Parity Migration](./phase-04-coding-mode-parity-migration.md): migrate current single coding path into a first-class `:coding` mode with parity guarantees.
5. [Phase 5 - Planning Mode Implementation](./phase-05-planning-mode-implementation.md): add a `:planning` mode that produces structured, decision-complete plans.
6. [Phase 6 - Engineering Mode Collaborative Design](./phase-06-engineering-mode-collaborative-design.md): add an `:engineering` mode for architecture discussion and decision capture.
7. [Phase 7 - Cross-Mode Recovery and Determinism](./phase-07-cross-mode-recovery-and-determinism.md): harden replay, recovery, and deterministic behavior across all modes.
8. [Phase 8 - Observability, Docs, Release, and Extension Model](./phase-08-observability-docs-release-and-extension-model.md): complete telemetry, documentation, release gates, and extension governance.

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

## Shared API / Interface Contract
- `JidoConversation.configure_mode(locator, mode, opts \\ [])`
- `JidoConversation.mode(locator)`
- `JidoConversation.supported_modes()`
- `JidoConversation.run(locator, input, opts \\ [])`
- `JidoConversation.interrupt_run(locator, reason \\ "interrupt_requested")`
- `JidoConversation.resume_run(locator, run_id, opts \\ [])`
- `Jido.Conversation.Mode` behavior
- `Jido.Conversation.Mode.Registry`
- Mode state additions in conversation runtime and projections:
  - `mode`
  - `mode_state`
  - `active_run`
  - `run_history`

## Shared Assumptions and Defaults
- Default mode is `:coding`.
- Only one active mode run is allowed per conversation at a time.
- Mode execution uses interruptible effect directives and current effect runtime (`:llm`, `:tool`, `:timer`).
- Existing coding APIs (`send_and_generate/3`, `generate_assistant_reply/2`, `await_generation/3`) remain available and delegate to coding-mode orchestration.
- Mode transitions and run lifecycle changes are represented in append-only journal entries/signals for replay safety.

## Cross-Phase Acceptance Scenarios
- [ ] M-1 A conversation can switch among `:coding`, `:planning`, and `:engineering` with deterministic run state.
- [ ] M-2 Interrupted runs can be resumed with deterministic continuation and stable run identity.
- [ ] M-3 Legacy coding APIs preserve behavior while executing through the new mode runtime.
- [ ] M-4 Planning mode produces decision-complete phase/section/task/subtask artifacts.
- [ ] M-5 Engineering mode captures alternatives, decisions, tradeoffs, and unresolved risks.
- [ ] M-6 Cross-project and cross-conversation isolation remains strict under concurrent mode workloads.
- [ ] M-7 Replay from journal reconstructs mode/run state equivalently to live execution.
- [ ] M-8 Telemetry and traceability are complete for run, step, interrupt, and resume lifecycles.
