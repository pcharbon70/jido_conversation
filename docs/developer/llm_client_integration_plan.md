# Unified LLM Client Integration Plan

This plan tracks implementation of a unified LLM client in `jido_conversation`
that can execute through:

- `JidoAI` (direct model/provider requests via ReqLLM)
- `JidoHarness` (coding CLI providers; model/provider owned by CLI/runtime)

## Goals

- Add one internal LLM client contract used by runtime effects.
- Keep reducer logic pure and backend-agnostic.
- Preserve event-first runtime semantics (`conv.effect.*`, `conv.out.*`).
- Support cancellation, retries, and timeouts consistently across backends.
- Support provider/model selection for `JidoAI` path.

## Non-goals

- Replacing tool or timer effect classes.
- Embedding rollout/deployment policy in this library.
- Hard-coding a single provider.

## Tracking Status

| Phase | Status | Description | Target PR Slice |
| --- | --- | --- | --- |
| Phase 0 | `completed` | Architecture contract and ADR | ADR + docs only |
| Phase 1 | `completed` | LLM domain model + backend behaviour | New `JidoConversation.LLM` modules |
| Phase 2 | `completed` | Config and backend resolution | Config wiring + validation |
| Phase 3 | `completed` | `JidoAI` adapter implementation | Adapter + tests |
| Phase 4 | `planned` | `JidoHarness` adapter implementation | Adapter + tests |
| Phase 5 | `planned` | Runtime effect integration | `EffectWorker` LLM path |
| Phase 6 | `planned` | Cancellation/retry semantics | Cancellation handles + policy tests |
| Phase 7 | `planned` | Event/projection parity hardening | Output mapping consistency |
| Phase 8 | `planned` | Observability and diagnostics | Telemetry + health snapshot |
| Phase 9 | `planned` | Reliability and replay parity matrix | Stress/parity/failure suites |
| Phase 10 | `planned` | Documentation and migration | User/developer docs |

## Phase 0: Architecture and contract baseline

### Objectives

- Lock the boundary and invariants before coding.

### Tasks

- Add ADR defining:
  - unified LLM client responsibility in `jido_conversation`
  - backend plugin model (`:jido_ai`, `:harness`)
  - cancellation semantics and error taxonomy
  - data ownership of provider/model selection by backend
- Define canonical runtime LLM lifecycle event expectations:
  - started
  - delta/thinking
  - completed
  - failed
  - canceled

### Deliverables

- ADR document
- Updated architecture notes in developer docs

### Exit criteria

- Team agreement on backend contract and normalization boundaries.

### Completion notes

- ADR completed:
  - `docs/adr/0005-unified-llm-client-backend-abstraction.md`
- Tracking plan and developer guide index added for phase-by-phase execution.

## Phase 1: LLM domain model and behaviour

### Objectives

- Introduce backend-agnostic types and callback contract.

### Tasks

- Add `JidoConversation.LLM` namespace:
  - `Request`
  - `Result`
  - `Event` (normalized stream event struct)
  - `Backend` behaviour
- Define `Backend` callbacks (minimum):
  - `start/2`
  - `stream/2` (or stream-capable start with normalized events)
  - `cancel/2`
  - `capabilities/0`
- Define normalized error categories:
  - config
  - auth
  - timeout
  - provider
  - transport
  - canceled
  - unknown

### Deliverables

- New LLM domain modules with typespecs and docs
- Unit tests for normalization and validation

### Exit criteria

- Both adapters can target one stable internal behaviour contract.

### Completion notes

- Added domain modules:
  - `lib/jido_conversation/llm/request.ex`
  - `lib/jido_conversation/llm/result.ex`
  - `lib/jido_conversation/llm/event.ex`
  - `lib/jido_conversation/llm/error.ex`
  - `lib/jido_conversation/llm/backend.ex`
- Added unit tests for normalization/validation and backend behaviour contract:
  - `test/jido_conversation/llm/request_test.exs`
  - `test/jido_conversation/llm/result_test.exs`
  - `test/jido_conversation/llm/event_test.exs`
  - `test/jido_conversation/llm/error_test.exs`
  - `test/jido_conversation/llm/backend_test.exs`
- Fixed boolean-field normalization for string/atom-key lookups to preserve explicit `false`.

## Phase 2: Configuration and backend resolution

### Objectives

- Add deterministic backend and model routing configuration.

### Tasks

- Extend `JidoConversation.Config` with `:llm` settings:
  - default backend
  - backend-specific config
  - default stream mode
  - model/provider defaults
- Add precedence policy:
  - effect payload override
  - conversation defaults
  - app config defaults
- Validate optional dependency availability:
  - explicit, actionable error when backend module not available

### Deliverables

- Config schema and validation updates
- Resolution helper module tests

### Exit criteria

- Backend selection is deterministic and test-covered.

### Completion notes

- Extended config schema and validation in:
  - `lib/jido_conversation/config.ex`
- Added LLM config accessors:
  - `llm/0`
  - `llm_default_backend/0`
  - `llm_backend_config/1`
  - `llm_backend_module/1`
- Added deterministic resolution helper with explicit precedence and module availability checks:
  - `lib/jido_conversation/llm/resolver.ex`
- Added tests for config defaults/merging/validation:
  - `test/jido_conversation/config_test.exs`
- Added tests for backend/model/provider resolution precedence and missing-module errors:
  - `test/jido_conversation/llm/resolver_test.exs`

## Phase 3: JidoAI backend adapter

### Objectives

- Implement direct LLM execution path with provider/model selection.

### Tasks

- Add `JidoConversation.LLM.Adapters.JidoAI`.
- Integrate with `Jido.AI`/ReqLLM generation + streaming paths.
- Support model/provider selection for this path:
  - alias
  - direct `provider:model`
  - generation options (temperature, max_tokens, timeout)
- Normalize usage/model/tool-call metadata into internal event format.

### Deliverables

- Working adapter with streaming and non-streaming support
- Adapter contract tests + provider/model selection tests

### Exit criteria

- Adapter emits canonical normalized events and final result metadata.

### Completion notes

- Added adapter implementation:
  - `lib/jido_conversation/llm/adapters/jido_ai.ex`
- Adapter includes:
  - dynamic `Jido.AI` / `Jido.AI.LLMClient` invocation (optional dependency-safe)
  - model/provider resolution with alias + `provider:model` support
  - normalized streaming lifecycle events (`started`, `delta`, `thinking`, `completed`, `failed`)
  - normalized result/usage/metadata mapping and error categorization
- Added adapter contract tests:
  - `test/jido_conversation/llm/adapters/jido_ai_test.exs`

## Phase 4: JidoHarness backend adapter

### Objectives

- Implement coding CLI runtime path via `JidoHarness`.

### Tasks

- Add `JidoConversation.LLM.Adapters.Harness`.
- Integrate with `Jido.Harness.run/2` or `run/3` event stream.
- Map harness event types into canonical normalized events.
- Preserve harness responsibility for provider/model resolution.
- Add best-effort final text extraction fallback for provider event variance.

### Deliverables

- Working harness adapter with normalized lifecycle output
- Adapter contract tests and event mapping tests

### Exit criteria

- Harness backend produces the same normalized lifecycle model used by runtime.

## Phase 5: Runtime effect integration

### Objectives

- Replace current simulated `:llm` effect execution with unified client.

### Tasks

- Integrate client in LLM branch of `Runtime.EffectWorker`.
- Keep existing effect manager orchestration and policy hooks.
- Emit lifecycle events through ingest adapters with canonical payload keys.
- Keep reducer pure and unchanged in architectural role.

### Deliverables

- End-to-end runtime path from `conv.in.message.received` to real backend calls
- Integration tests for both backends

### Exit criteria

- Runtime executes real LLM effects through selected backend.

## Phase 6: Cancellation, retries, and timeout semantics

### Objectives

- Make cancellation and retry behavior consistent and observable.

### Tasks

- Persist backend cancellation handle/session state in effect execution context.
- Implement backend-specific cancellation:
  - JidoAI stream cancel handle
  - Harness `cancel(provider, session_id)` when available
- Apply retry policy only to retryable failures.
- Ensure canceled effects do not emit final completed outputs.

### Deliverables

- Cancellation integration tests
- Retry classification tests

### Exit criteria

- Cancel requests deterministically stop active LLM work and emit canceled lifecycle.

## Phase 7: Output and projection parity hardening

### Objectives

- Keep `conv.out.*` behavior stable while enriching metadata.

### Tasks

- Standardize effect payload keys consumed by reducer output directives.
- Validate `conv.out.assistant.delta` and `conv.out.assistant.completed` parity across backends.
- Ensure tool call/tool status output remains coherent when produced by backend data.

### Deliverables

- Projection and reducer-output parity tests

### Exit criteria

- Timeline and LLM context projections stay consistent regardless of backend.

## Phase 8: Observability and diagnostics

### Objectives

- Provide host-visible runtime insight for backend behavior.

### Tasks

- Add telemetry metadata dimensions:
  - backend
  - provider
  - model
  - cancellation result
  - retry category
- Add metrics for:
  - llm start/completion/failure counts
  - llm cancel latency
  - stream duration and chunk counts
- Extend telemetry snapshot integration where useful.

### Deliverables

- Telemetry tests and docs

### Exit criteria

- Host app can diagnose LLM backend health and failure classes quickly.

## Phase 9: Reliability and replay parity matrix

### Objectives

- Validate correctness under load and failure scenarios.

### Tasks

- Add backend matrix tests:
  - JidoAI happy path + failures
  - Harness happy path + provider variance
- Add timeout/cancel race tests.
- Add replay parity tests using sampled traces from both backends.

### Deliverables

- Extended determinism/reliability suite

### Exit criteria

- Replay/live parity remains stable with unified client in place.

## Phase 10: Documentation and migration

### Objectives

- Make adoption and operation straightforward for hosts.

### Tasks

- Add user guide for configuring backend, model selection, and overrides.
- Add developer guide for backend adapter contract and normalized lifecycle events.
- Add migration notes for hosts using prior simulated LLM effect behavior.

### Deliverables

- Updated docs in `docs/user/` and `docs/developer/`

### Exit criteria

- Hosts can configure and run either backend without reading source code.

## Cross-phase quality gates

- Reducer purity preserved (no blocking side effects in reducer path).
- Contract integrity at ingest boundary.
- Cancellation responsiveness maintained under load.
- Replay/live parity maintained for state and projections.
- Pre-commit quality gate remains green:
  - `mix test`
  - `mix credo --strict`
  - `mix dialyzer`

## Suggested implementation order for PRs

1. Phase 0 + Phase 1 (contract + types)
2. Phase 2 (config + resolution)
3. Phase 3 (JidoAI adapter)
4. Phase 4 (Harness adapter)
5. Phase 5 + Phase 6 (runtime integration + cancellation)
6. Phase 7 + Phase 8 (output parity + telemetry)
7. Phase 9 + Phase 10 (hardening + docs)

## Open decisions to track explicitly

- Stream-first vs non-stream-first default for each backend.
- Canonical representation for provider-specific reasoning/thinking chunks.
- Minimum metadata required for model/provider attribution in `conv.effect.*`.
- Retryability classification map per backend error shape.
