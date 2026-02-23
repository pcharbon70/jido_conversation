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
| Phase 4 | `completed` | `JidoHarness` adapter implementation | Adapter + tests |
| Phase 5 | `completed` | Runtime effect integration | `EffectWorker` LLM path |
| Phase 6 | `completed` | Cancellation/retry semantics | Cancellation handles + policy tests |
| Phase 7 | `completed` | Event/projection parity hardening | Output mapping consistency |
| Phase 8 | `completed` | Observability and diagnostics | Telemetry + health snapshot |
| Phase 9 | `completed` | Reliability and replay parity matrix | Stress/parity/failure suites |
| Phase 10 | `completed` | Documentation and migration | User/developer docs |
| Phase 11 | `completed` | Open-decision closure and retry policy hardening | Retry map + contract clarifications |
| Phase 12 | `completed` | Runtime retry policy matrix | End-to-end adapter retry classification |
| Phase 13 | `completed` | Stream-path retry policy matrix | End-to-end stream adapter retry classification |
| Phase 14 | `completed` | Retry telemetry parity matrix | Retry counters and backend lifecycle telemetry parity |
| Phase 15 | `completed` | Stream retry telemetry parity matrix | Stream retry counters and lifecycle telemetry parity |
| Phase 16 | `completed` | Cancel telemetry parity matrix | Cancel result and lifecycle telemetry parity across backends |
| Phase 17 | `completed` | Timeout/transport retry category telemetry parity | Retry category counters for timeout and transport classes |
| Phase 18 | `completed` | Stream timeout/transport retry telemetry parity | Stream retry category counters for timeout and transport classes |
| Phase 19 | `completed` | Auth non-retryable runtime parity | Non-stream auth classification and retry telemetry invariants |
| Phase 20 | `completed` | Stream auth non-retryable runtime parity | Stream auth classification and retry telemetry invariants |
| Phase 21 | `completed` | Unknown non-retryable runtime parity | Non-stream unknown classification and retry telemetry invariants |
| Phase 22 | `completed` | Stream unknown non-retryable runtime parity | Stream unknown classification and retry telemetry invariants |
| Phase 23 | `completed` | Config non-retryable runtime parity | Non-stream config classification and retry telemetry invariants |
| Phase 24 | `completed` | Stream config non-retryable runtime parity | Stream config classification and retry telemetry invariants |
| Phase 25 | `completed` | Canceled non-retryable runtime parity | Non-stream canceled classification and retry telemetry invariants |
| Phase 26 | `completed` | Stream canceled non-retryable runtime parity | Stream canceled classification and retry telemetry invariants |
| Phase 27 | `completed` | Provider non-retryable runtime parity hardening | Non-stream provider failed payload classification parity + telemetry invariants |
| Phase 28 | `completed` | Stream provider non-retryable runtime parity hardening | Stream provider failed payload classification parity + telemetry invariants |
| Phase 29 | `completed` | Non-stream retry progress payload parity hardening | Retrying progress error-category/retryable invariants across retryable categories |
| Phase 30 | `completed` | Stream retry progress payload parity hardening | Stream retrying progress error-category/retryable invariants across retryable categories |
| Phase 31 | `completed` | Telemetry retry-category parity hardening | Retry-category precedence/fallback invariants in telemetry aggregation |
| Phase 32 | `completed` | Effect-manager LLM retry lifecycle parity hardening | Retrying progress payload classification and telemetry invariants in effect runtime tests |
| Phase 33 | `completed` | Effect-manager LLM start-path retry parity hardening | Non-stream retrying progress payload classification and telemetry invariants in effect runtime tests |
| Phase 34 | `completed` | Effect-manager LLM start-path non-retry parity hardening | Non-stream non-retryable failed payload classification and retry telemetry invariants in effect runtime tests |
| Phase 35 | `completed` | Effect-manager LLM stream-path non-retry parity hardening | Stream non-retryable failed payload classification and retry telemetry invariants in effect runtime tests |
| Phase 36 | `completed` | Effect-manager LLM stream-path retry cardinality parity hardening | Stream retry-attempt bounds, retrying lifecycle cardinality, and failed-telemetry invariants in effect runtime tests |
| Phase 37 | `completed` | Effect-manager LLM start-path retry cardinality parity hardening | Non-stream retry-attempt bounds, retrying lifecycle cardinality, and failed-telemetry invariants in effect runtime tests |
| Phase 38 | `completed` | Effect-manager LLM stream-path retry-attempt-start parity hardening | Stream retry-attempt-start lifecycle cardinality and attempt labeling invariants in effect runtime tests |
| Phase 39 | `completed` | Effect-manager LLM start-path retry-attempt-start parity hardening | Non-stream retry-attempt-start lifecycle cardinality and attempt labeling invariants in effect runtime tests |
| Phase 40 | `completed` | Effect-manager LLM cancel lifecycle/telemetry parity hardening | Cancel lifecycle payload/cardinality and cancel telemetry invariants in effect runtime tests |
| Phase 41 | `completed` | Effect-manager LLM cancel-without-context parity hardening | Cancel lifecycle and telemetry invariants when execution_ref is unavailable in effect runtime tests |
| Phase 42 | `completed` | Effect-manager LLM cancel-failed parity hardening | Cancel lifecycle payload and telemetry invariants when backend cancellation returns failure in effect runtime tests |
| Phase 43 | `completed` | Effect-manager LLM cancel attribution parity hardening | Cancel-failed lifecycle backend/provider/model attribution and backend lifecycle telemetry invariants in effect runtime tests |
| Phase 44 | `completed` | Effect-manager LLM cancel cause-link parity hardening | Explicit cancel `cause_id` lifecycle linkage and backward trace-chain invariants in effect runtime tests |
| Phase 45 | `completed` | Effect-manager LLM cancel invalid-cause fallback parity hardening | Invalid cancel `cause_id` uncoupled lifecycle tracing and cancel telemetry invariants in effect runtime tests |
| Phase 46 | `completed` | Effect-manager LLM cancel-failed cause-link parity hardening | Cancel-failed explicit `cause_id` lifecycle linkage and failed-cancel telemetry invariants in effect runtime tests |
| Phase 47 | `completed` | Effect-manager LLM cancel-failed invalid-cause fallback parity hardening | Cancel-failed invalid `cause_id` uncoupled lifecycle tracing and failed-cancel telemetry invariants in effect runtime tests |
| Phase 48 | `completed` | Effect-manager LLM cancel-failed invalid-cause attribution parity hardening | Cancel-failed invalid `cause_id` attribution payload/category and backend lifecycle telemetry invariants in effect runtime tests |
| Phase 49 | `completed` | Cancel-failed invalid-cause fallback matrix parity hardening | Cross-backend (`jido_ai`/`harness`) invalid `cause_id` fallback tracing and failed-cancel telemetry/backend attribution invariants in runtime matrix tests |
| Phase 50 | `completed` | Cancel-failed cause-link matrix parity hardening | Cross-backend (`jido_ai`/`harness`) explicit `cause_id` trace-chain linkage and failed-cancel telemetry/backend attribution invariants in runtime matrix tests |
| Phase 51 | `completed` | Cancel-ok cause-link matrix parity hardening | Cross-backend (`jido_ai`/`harness`) explicit `cause_id` trace-chain linkage and cancel-ok telemetry/backend lifecycle invariants in runtime matrix tests |
| Phase 52 | `completed` | Cancel-ok invalid-cause fallback matrix parity hardening | Cross-backend (`jido_ai`/`harness`) invalid `cause_id` fallback tracing and cancel-ok telemetry/backend lifecycle attribution invariants in runtime matrix tests |
| Phase 53 | `completed` | Cancel-not-available invalid-cause fallback matrix parity hardening | Cross-backend (`jido_ai`/`harness`) invalid `cause_id` fallback tracing and cancel-not-available telemetry/backend lifecycle attribution invariants in runtime matrix tests |
| Phase 54 | `completed` | Cancel-not-available cause-link matrix parity hardening | Cross-backend (`jido_ai`/`harness`) explicit `cause_id` trace-chain linkage and cancel-not-available telemetry/backend lifecycle attribution invariants in runtime matrix tests |
| Phase 55 | `completed` | Cancel-not-available baseline attribution matrix parity hardening | Cross-backend (`jido_ai`/`harness`) baseline cancel-not-available payload attribution and backend lifecycle telemetry invariants in runtime matrix tests |
| Phase 56 | `completed` | Cancel-failed baseline attribution matrix parity hardening | Cross-backend (`jido_ai`/`harness`) baseline cancel-failed payload attribution/error metadata and backend lifecycle telemetry invariants in runtime matrix tests |
| Phase 57 | `completed` | Cancel-ok baseline attribution matrix parity hardening | Cross-backend (`jido_ai`/`harness`) baseline cancel-ok payload attribution and backend lifecycle/retry-category telemetry invariants in runtime matrix tests |
| Phase 58 | `completed` | Cancel baseline terminal-exclusivity matrix parity hardening | Cross-backend baseline cancel scenarios enforce single terminal `canceled` lifecycle with no `completed`/`failed` regression in runtime matrix tests |
| Phase 59 | `completed` | Cancel cause-variant terminal-exclusivity matrix parity hardening | Cross-backend cause-link/invalid-cause cancel scenarios enforce single terminal `canceled` lifecycle with no `completed`/`failed` regression in runtime matrix tests |

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

### Completion notes

- Added adapter implementation:
  - `lib/jido_conversation/llm/adapters/harness.ex`
- Adapter includes:
  - dynamic `Jido.Harness` invocation (optional dependency-safe)
  - `run/2` and `run/3` integration with prompt + options mapping
  - normalized streaming lifecycle events (`started`, `delta`, `thinking`, `completed`, `failed`, `canceled`)
  - best-effort fallback extraction for provider event variance (`assistant`, `result`, `output_text` shapes)
  - explicit cancellation support through `Jido.Harness.cancel/2`
- Added adapter contract tests:
  - `test/jido_conversation/llm/adapters/harness_test.exs`

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

### Completion notes

- Integrated real LLM execution into runtime effect worker:
  - `lib/jido_conversation/runtime/effect_worker.ex`
- Runtime now:
  - resolves backend/module/provider/model/stream settings via `LLM.Resolver`
  - builds normalized `LLM.Request` values from effect input payloads
  - executes adapter `start/2` or `stream/3` based on resolved stream mode
  - maps streaming delta/thinking events to `conv.effect.llm.generation.progress`
  - emits normalized completion/failure payloads for reducer/output projections
- Kept tool/timer execution path and effect-manager orchestration unchanged.
- Added runtime integration coverage for real LLM backend execution through effect manager:
  - `test/jido_conversation/runtime/effect_manager_test.exs`
- Updated assistant-delta extraction to avoid treating generic progress statuses as content:
  - `lib/jido_conversation/runtime/reducer.ex`

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

### Completion notes

- Added backend cancellation context tracking in runtime worker state:
  - worker now captures backend/module/options/execution reference per attempt
  - streaming metadata events can contribute execution refs used for cancellation
- Added backend-aware cancellation execution in `Runtime.EffectWorker`:
  - cancel path now calls backend `cancel/2` when execution reference is available
  - cancellation lifecycle payload records backend cancellation outcome metadata
- Tightened retry policy to apply only to retryable failures:
  - non-retryable `LLM.Error` failures no longer requeue attempts
- Added and expanded runtime integration tests:
  - non-retryable backend errors are not retried
  - canceling an active conversation triggers backend cancel and avoids completed output
- Extended adapter metadata for cancellation handles:
  - `JidoAI` streaming started event includes execution reference metadata
  - `Harness` stream and terminal events include session/execution reference metadata

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

### Completion notes

- Standardized reducer output payload mapping for `conv.effect.llm.generation.*`:
  - assistant delta/completed outputs now include normalized lifecycle metadata
    (status, provider, model, backend, sequence/attempt where available)
  - reducer now preserves and forwards normalized `usage` and selected metadata
    fields from backend result payloads
- Hardened tool status output coherence:
  - tool lifecycle projection payload now includes explicit `status` in addition
    to `message`
  - tool identifier fields (`tool_name`, `tool_call_id`) are propagated when
    present
  - LLM lifecycle events can emit `conv.out.tool.status` when backend payloads
    include tool call/status signals
- Hardened timeline projection metadata parity:
  - timeline assistant and tool entries retain standardized metadata keys across
    backends, including usage and metadata maps when present
- Added/expanded parity-focused tests:
  - reducer tests for backend-shaped payload normalization and tool status
    coherence
  - timeline projection metadata preservation tests
  - harness adapter stream normalization regression coverage

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

### Completion notes

- Added LLM runtime telemetry events emitted by effect workers:
  - `[:jido_conversation, :runtime, :llm, :lifecycle]`
  - `[:jido_conversation, :runtime, :llm, :cancel]`
  - `[:jido_conversation, :runtime, :llm, :retry]`
- Added metadata dimensions on LLM runtime telemetry:
  - backend
  - provider
  - model
  - cancel result
  - retry category
- Extended `JidoConversation.Telemetry` aggregation state and snapshot with
  LLM-specific metrics:
  - lifecycle counts (overall and grouped by backend)
  - stream duration summary
  - stream chunk totals (delta/thinking/total)
  - cancel latency summary
  - retry category counters
  - cancellation result counters
- Added tests for telemetry aggregation and runtime integration:
  - expanded telemetry snapshot tests for LLM lifecycle/retry/cancel metrics
  - runtime effect-manager test validating LLM execution updates telemetry
- Updated host-facing operations docs to include new LLM telemetry fields and
  event families.

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

### Completion notes

- Added runtime backend matrix coverage for both backend paths:
  - `jido_ai`-style streaming happy path
  - `harness`-style streaming happy path with provider variance
- Added timeout/cancel race coverage for LLM effects:
  - validates a single terminal lifecycle outcome under timeout/cancel contention
  - confirms completed lifecycle is never emitted in race termination paths
- Added replay/live parity checks for sampled traces generated through both
  backend paths:
  - verifies `Projections.timeline/2` parity against replay reconstruction
  - verifies `Projections.llm_context/2` parity against replay reconstruction
- Extended determinism/reliability suite with:
  - `test/jido_conversation/runtime/llm_reliability_matrix_test.exs`

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

### Completion notes

- Added user-facing backend configuration guide:
  - `docs/user/llm_backend_configuration.md`
  - includes backend selection, provider/model routing, and override precedence
- Added developer-facing adapter contract guide:
  - `docs/developer/llm_backend_adapter_contract.md`
  - documents callback contract, normalized lifecycle mapping, error taxonomy,
    and cancellation expectations
- Added migration notes for prior simulated LLM effect behavior:
  - `docs/developer/llm_migration_notes.md`
  - captures configuration requirements, payload changes, retry/cancel semantics,
    and observability updates
- Updated guide indexes and navigation links:
  - `docs/user/README.md`
  - `docs/developer/README.md`
  - `docs/user/getting_started.md`

## Phase 11: Open-decision closure and retry policy hardening

### Objectives

- Resolve the remaining explicit open decisions in the LLM integration plan.
- Tighten retryability classification to avoid retrying non-retryable provider
  request errors.

### Tasks

- Codify explicit HTTP retryability mapping for built-in adapters.
- Add adapter tests covering retryable and non-retryable provider status paths.
- Clarify canonical reasoning/delta representation and attribution metadata
  expectations in developer adapter contract docs.

### Deliverables

- Adapter normalization updates and regression tests.
- Updated developer contract documentation for decision outcomes.

### Exit criteria

- Adapter retryability behavior is deterministic for common HTTP error classes.
- Previously open architecture decisions are explicitly documented.

### Completion notes

- Updated adapter error normalization retryability for HTTP status classes:
  - `lib/jido_conversation/llm/adapters/jido_ai.ex`
  - `lib/jido_conversation/llm/adapters/harness.ex`
- Added regression tests for non-retryable vs retryable provider statuses:
  - `test/jido_conversation/llm/adapters/jido_ai_test.exs`
  - `test/jido_conversation/llm/adapters/harness_test.exs`
- Updated developer contract guide with resolved decision details:
  - `docs/developer/llm_backend_adapter_contract.md`

## Phase 12: Runtime retry policy matrix

### Objectives

- Validate retry classification behavior through the live runtime path rather
  than adapter unit tests only.
- Prove retry/no-retry outcomes for both built-in adapters under representative
  HTTP error classes.

### Tasks

- Add runtime matrix tests that exercise `EffectManager` with built-in adapters:
  - `JidoConversation.LLM.Adapters.JidoAI`
  - `JidoConversation.LLM.Adapters.Harness`
- Verify `422` provider failures do not retry.
- Verify `503` provider failures retry and complete within max attempts.
- Verify lifecycle stream reflects retry state consistently.

### Deliverables

- Runtime retry policy matrix test suite.

### Exit criteria

- Runtime behavior matches documented retryability policy for both adapters.

### Completion notes

- Added end-to-end retry policy matrix coverage:
  - `test/jido_conversation/runtime/llm_retry_policy_matrix_test.exs`
- Matrix verifies:
  - non-retryable provider `422` paths emit single-attempt failure (no retry)
  - retryable provider `503` paths emit retry lifecycle and eventual completion
  - behavior parity across `jido_ai` and `harness` backends

## Phase 13: Stream-path retry policy matrix

### Objectives

- Validate retry classification behavior through stream execution paths for both
  built-in adapters.
- Ensure retry policy parity between start-path and stream-path runtime flows.

### Tasks

- Add runtime stream-mode matrix tests for:
  - `JidoConversation.LLM.Adapters.JidoAI`
  - `JidoConversation.LLM.Adapters.Harness`
- Verify stream-mode `422` failures do not retry.
- Verify stream-mode `503` failures retry and eventually complete.
- Verify lifecycle stream still reports retry transitions consistently.

### Deliverables

- Runtime stream retry policy matrix test suite.

### Exit criteria

- Stream runtime behavior matches documented retryability policy for both
  adapters.

### Completion notes

- Added end-to-end stream retry policy matrix coverage:
  - `test/jido_conversation/runtime/llm_retry_policy_stream_matrix_test.exs`
- Stream matrix verifies:
  - non-retryable provider `422` paths emit single-attempt failure
  - retryable provider `503` paths emit retry lifecycle and eventual completion
  - parity across `jido_ai` and `harness` stream execution paths

## Phase 14: Retry telemetry parity matrix

### Objectives

- Ensure retry policy behavior is reflected consistently in runtime telemetry.
- Validate parity for retry/no-retry paths across both built-in adapters.

### Tasks

- Extend runtime retry matrix coverage with telemetry assertions:
  - `llm.retry_by_category`
  - `llm.lifecycle_by_backend`
- Verify non-retryable `422` paths increment backend failure lifecycle counters
  without incrementing retry counters.
- Verify retryable `503` paths increment both retry counters and backend
  completion lifecycle counters.

### Deliverables

- Runtime retry matrix tests with telemetry parity assertions.

### Exit criteria

- Telemetry snapshot reflects retry policy outcomes deterministically for both
  adapters.

### Completion notes

- Extended end-to-end runtime retry matrix tests with telemetry parity checks:
  - `test/jido_conversation/runtime/llm_retry_policy_matrix_test.exs`
- Added explicit assertions for:
  - no `provider` retry increment on non-retryable `422` failures
  - `provider` retry increments on retryable `503` failures
  - backend lifecycle counter progression (`failed`/`completed`) per adapter

## Phase 15: Stream retry telemetry parity matrix

### Objectives

- Ensure stream-path retry behavior is reflected consistently in telemetry.
- Validate retry/no-retry telemetry parity for both built-in adapters in
  stream mode.

### Tasks

- Extend stream retry matrix coverage with telemetry snapshot assertions:
  - `llm.retry_by_category`
  - `llm.lifecycle_counts`
- Verify stream non-retryable `422` paths increment failed lifecycle telemetry
  without incrementing provider retry counters.
- Verify stream retryable `503` paths increment provider retry counters and
  completion lifecycle telemetry.

### Deliverables

- Stream runtime retry matrix tests with telemetry parity assertions.

### Exit criteria

- Stream telemetry deterministically reflects documented retry policy outcomes.

### Completion notes

- Extended stream retry policy matrix with telemetry parity checks:
  - `test/jido_conversation/runtime/llm_retry_policy_stream_matrix_test.exs`
- Added explicit assertions for:
  - no `provider` retry increment on non-retryable stream `422` failures
  - `provider` retry increments on retryable stream `503` failures
  - stream lifecycle counter progression for failed/completed outcomes

## Phase 16: Cancel telemetry parity matrix

### Objectives

- Validate cancellation telemetry parity across both built-in backends.
- Ensure cancellation outcome classes are reflected consistently in telemetry.

### Tasks

- Add runtime cancellation matrix tests for both `jido_ai` and `harness`
  backend paths.
- Verify telemetry classification for:
  - backend cancellation success (`ok`)
  - cancellation not attempted due to missing execution reference
    (`not_available`)
  - backend cancellation error (`failed`)
- Verify canceled lifecycle emission and no completed lifecycle emission in all
  cancel outcomes.

### Deliverables

- Runtime cancel telemetry matrix test suite.

### Exit criteria

- Cancellation telemetry and lifecycle behavior are deterministic and backend
  parity is maintained.

### Completion notes

- Added end-to-end cancel telemetry parity coverage:
  - `test/jido_conversation/runtime/llm_cancel_telemetry_matrix_test.exs`
- Matrix verifies:
  - `ok`, `not_available`, and `failed` cancel result classes across backends
  - canceled lifecycle emitted without completed lifecycle on cancel paths
  - cancel telemetry counters and latency snapshots increment per cancellation

## Phase 17: Timeout/transport retry category telemetry parity

### Objectives

- Validate retry category telemetry parity for timeout and transport failure
  classes across built-in adapters.
- Ensure runtime retry telemetry reflects adapter-normalized categories beyond
  provider-status-based retries.

### Tasks

- Extend runtime retry matrix coverage to include timeout and transport recovery
  scenarios for:
  - `jido_ai` backend path
  - `harness` backend path
- Verify these paths retry and complete successfully.
- Verify telemetry `llm.retry_by_category` increments for:
  - `timeout`
  - `transport`

### Deliverables

- Runtime retry matrix tests covering timeout/transport telemetry categories.

### Exit criteria

- Timeout/transport retry categories are emitted and counted deterministically
  across both built-in adapters.

### Completion notes

- Extended runtime retry policy matrix with timeout/transport category coverage:
  - `test/jido_conversation/runtime/llm_retry_policy_matrix_test.exs`
- Added explicit assertions for:
  - timeout retry category increments and completion for both backends
  - transport retry category increments and completion for both backends

## Phase 18: Stream timeout/transport retry telemetry parity

### Objectives

- Validate timeout and transport retry category telemetry parity across stream
  execution paths for built-in adapters.
- Ensure stream retry categorization remains consistent with non-stream runtime
  behavior.

### Tasks

- Extend runtime stream retry matrix coverage with timeout/transport recovery
  scenarios for:
  - `jido_ai` backend stream path
  - `harness` backend stream path
- Verify timeout/transport stream scenarios retry and complete successfully.
- Verify telemetry `llm.retry_by_category` increments for:
  - `timeout`
  - `transport`

### Deliverables

- Runtime stream retry matrix tests covering timeout/transport retry category
  telemetry.

### Exit criteria

- Stream timeout/transport retries emit deterministic category telemetry
  increments across both built-in adapters.

### Completion notes

- Extended stream retry policy matrix with timeout/transport category coverage:
  - `test/jido_conversation/runtime/llm_retry_policy_stream_matrix_test.exs`
- Added explicit assertions for:
  - stream timeout retry category increments and completion for both backends
  - stream transport retry category increments and completion for both backends

## Phase 19: Auth non-retryable runtime parity

### Objectives

- Validate runtime auth classification parity across non-stream execution paths
  for built-in adapters.
- Ensure auth failures remain non-retryable and do not increment retry category
  counters.

### Tasks

- Extend runtime retry matrix coverage with auth failure scenarios for:
  - `jido_ai` backend path (`401`)
  - `harness` backend path (`403`)
- Verify these auth failures do not retry and terminate with failed lifecycle.
- Verify failed lifecycle payload includes:
  - `error_category: "auth"`
  - `retryable?: false`
- Verify telemetry `llm.retry_by_category["auth"]` remains unchanged for
  non-retryable auth failures.

### Deliverables

- Runtime retry matrix tests covering auth non-retryable classification and
  telemetry invariants.

### Exit criteria

- Auth runtime failures are classified deterministically and never retried
  across both built-in adapters in non-stream mode.

### Completion notes

- Extended runtime retry policy matrix with auth non-retryable coverage:
  - `test/jido_conversation/runtime/llm_retry_policy_matrix_test.exs`
- Added explicit assertions for:
  - no retry attempts on `401/403` auth failures
  - failed lifecycle payload category/retryable invariants (`auth`, `false`)
  - no `auth` retry counter increments in telemetry snapshot

## Phase 20: Stream auth non-retryable runtime parity

### Objectives

- Validate runtime auth classification parity across stream execution paths for
  built-in adapters.
- Ensure stream auth failures remain non-retryable and do not increment retry
  category counters.

### Tasks

- Extend runtime stream retry matrix coverage with auth failure scenarios for:
  - `jido_ai` backend stream path (`401`)
  - `harness` backend stream path (`403`)
- Verify auth stream failures do not retry and terminate with failed lifecycle.
- Verify failed lifecycle payload includes:
  - `error_category: "auth"`
  - `retryable?: false`
- Verify telemetry `llm.retry_by_category["auth"]` remains unchanged for
  non-retryable stream auth failures.

### Deliverables

- Runtime stream retry matrix tests covering auth non-retryable classification
  and telemetry invariants.

### Exit criteria

- Auth stream runtime failures are classified deterministically and never
  retried across both built-in adapters.

### Completion notes

- Extended stream retry policy matrix with auth non-retryable coverage:
  - `test/jido_conversation/runtime/llm_retry_policy_stream_matrix_test.exs`
- Added explicit assertions for:
  - no retry attempts on stream `401/403` auth failures
  - stream failed lifecycle payload category/retryable invariants
    (`auth`, `false`)
  - no `auth` retry counter increments in telemetry snapshot for stream paths

## Phase 21: Unknown non-retryable runtime parity

### Objectives

- Validate runtime fallback classification parity across non-stream execution
  paths for built-in adapters.
- Ensure unknown failures remain non-retryable and do not increment retry
  category counters.

### Tasks

- Extend runtime retry matrix coverage with unknown failure scenarios for:
  - `jido_ai` backend path (unclassified map error)
  - `harness` backend path (unclassified map error)
- Verify unknown failures do not retry and terminate with failed lifecycle.
- Verify failed lifecycle payload includes:
  - `error_category: "unknown"`
  - `retryable?: false`
- Verify telemetry `llm.retry_by_category["unknown"]` remains unchanged for
  non-retryable unknown failures.

### Deliverables

- Runtime retry matrix tests covering unknown non-retryable fallback
  classification and telemetry invariants.

### Exit criteria

- Unknown runtime failures are classified deterministically and never retried
  across both built-in adapters in non-stream mode.

### Completion notes

- Extended runtime retry policy matrix with unknown non-retryable coverage:
  - `test/jido_conversation/runtime/llm_retry_policy_matrix_test.exs`
- Added explicit assertions for:
  - no retry attempts on unknown classified failures
  - failed lifecycle payload category/retryable invariants (`unknown`, `false`)
  - no `unknown` retry counter increments in telemetry snapshot

## Phase 22: Stream unknown non-retryable runtime parity

### Objectives

- Validate runtime fallback classification parity across stream execution paths
  for built-in adapters.
- Ensure stream unknown failures remain non-retryable and do not increment
  retry category counters.

### Tasks

- Extend runtime stream retry matrix coverage with unknown failure scenarios
  for:
  - `jido_ai` backend stream path (unclassified map error)
  - `harness` backend stream path (unclassified map error)
- Verify unknown stream failures do not retry and terminate with failed
  lifecycle.
- Verify failed lifecycle payload includes:
  - `error_category: "unknown"`
  - `retryable?: false`
- Verify telemetry `llm.retry_by_category["unknown"]` remains unchanged for
  non-retryable stream unknown failures.

### Deliverables

- Runtime stream retry matrix tests covering unknown non-retryable fallback
  classification and telemetry invariants.

### Exit criteria

- Unknown stream runtime failures are classified deterministically and never
  retried across both built-in adapters.

### Completion notes

- Updated Harness stream failure normalization to preserve `unknown` category
  for structured map errors:
  - `lib/jido_conversation/llm/adapters/harness.ex`
- Extended stream retry policy matrix with unknown non-retryable coverage:
  - `test/jido_conversation/runtime/llm_retry_policy_stream_matrix_test.exs`
- Added explicit assertions for:
  - no retry attempts on unknown classified stream failures
  - failed stream lifecycle payload category/retryable invariants
    (`unknown`, `false`)
  - no `unknown` retry counter increments in telemetry snapshot for stream
    paths

## Phase 23: Config non-retryable runtime parity

### Objectives

- Validate runtime config classification parity across non-stream execution
  paths for built-in adapters.
- Ensure config failures remain non-retryable and do not increment retry
  category counters.

### Tasks

- Extend runtime retry matrix coverage with config failure scenarios for:
  - `jido_ai` backend path (`ArgumentError` configuration failure)
  - `harness` backend path (`ArgumentError` configuration failure)
- Verify config failures do not retry and terminate with failed lifecycle.
- Verify failed lifecycle payload includes:
  - `error_category: "config"`
  - `retryable?: false`
- Verify telemetry `llm.retry_by_category["config"]` remains unchanged for
  non-retryable config failures.

### Deliverables

- Runtime retry matrix tests covering config non-retryable classification and
  telemetry invariants.

### Exit criteria

- Config runtime failures are classified deterministically and never retried
  across both built-in adapters in non-stream mode.

### Completion notes

- Extended runtime retry policy matrix with config non-retryable coverage:
  - `test/jido_conversation/runtime/llm_retry_policy_matrix_test.exs`
- Added explicit assertions for:
  - no retry attempts on config-classified failures
  - failed lifecycle payload category/retryable invariants (`config`, `false`)
  - no `config` retry counter increments in telemetry snapshot

## Phase 24: Stream config non-retryable runtime parity

### Objectives

- Validate runtime config classification parity across stream execution paths
  for built-in adapters.
- Ensure stream config failures remain non-retryable and do not increment retry
  category counters.

### Tasks

- Extend runtime stream retry matrix coverage with config failure scenarios
  for:
  - `jido_ai` backend stream path (`ArgumentError` configuration failure)
  - `harness` backend stream path (`ArgumentError` configuration failure)
- Verify config stream failures do not retry and terminate with failed
  lifecycle.
- Verify failed lifecycle payload includes:
  - `error_category: "config"`
  - `retryable?: false`
- Verify telemetry `llm.retry_by_category["config"]` remains unchanged for
  non-retryable stream config failures.

### Deliverables

- Runtime stream retry matrix tests covering config non-retryable
  classification and telemetry invariants.

### Exit criteria

- Config stream runtime failures are classified deterministically and never
  retried across both built-in adapters.

### Completion notes

- Extended stream retry policy matrix with config non-retryable coverage:
  - `test/jido_conversation/runtime/llm_retry_policy_stream_matrix_test.exs`
- Added explicit assertions for:
  - no retry attempts on config-classified stream failures
  - failed stream lifecycle payload category/retryable invariants
    (`config`, `false`)
  - no `config` retry counter increments in telemetry snapshot for stream
    paths

## Phase 25: Canceled non-retryable runtime parity

### Objectives

- Validate runtime canceled classification parity across non-stream execution
  paths for built-in adapters.
- Ensure canceled failures remain non-retryable and do not increment retry
  category counters.

### Tasks

- Extend runtime retry matrix coverage with canceled failure scenarios for:
  - `jido_ai` backend path (`reason: :canceled`)
  - `harness` backend path (`reason: :canceled`)
- Verify canceled failures do not retry and terminate with failed lifecycle.
- Verify failed lifecycle payload includes:
  - `error_category: "canceled"`
  - `retryable?: false`
- Verify telemetry `llm.retry_by_category["canceled"]` remains unchanged for
  non-retryable canceled failures.

### Deliverables

- Runtime retry matrix tests covering canceled non-retryable classification and
  telemetry invariants.
- Adapter normalization update for `jido_ai` canceled reason mapping.

### Exit criteria

- Canceled runtime failures are classified deterministically and never retried
  across both built-in adapters in non-stream mode.

### Completion notes

- Updated `jido_ai` error normalization to classify canceled reasons:
  - `lib/jido_conversation/llm/adapters/jido_ai.ex`
- Added adapter normalization coverage:
  - `test/jido_conversation/llm/adapters/jido_ai_test.exs`
- Extended runtime retry policy matrix with canceled non-retryable coverage:
  - `test/jido_conversation/runtime/llm_retry_policy_matrix_test.exs`
- Added explicit assertions for:
  - no retry attempts on canceled-classified failures
  - failed lifecycle payload category/retryable invariants
    (`canceled`, `false`)
  - no `canceled` retry counter increments in telemetry snapshot

## Phase 26: Stream canceled non-retryable runtime parity

### Objectives

- Validate runtime canceled classification parity across stream execution paths
  for built-in adapters.
- Ensure canceled stream failures remain non-retryable and do not increment
  retry category counters.

### Tasks

- Extend stream runtime retry matrix coverage with canceled failure scenarios
  for:
  - `jido_ai` backend stream path (`reason: :canceled`)
  - `harness` backend stream path (`reason: :canceled`)
- Verify canceled stream failures do not retry and terminate with failed
  lifecycle.
- Verify failed stream lifecycle payload includes:
  - `error_category: "canceled"`
  - `retryable?: false`
- Verify telemetry `llm.retry_by_category["canceled"]` remains unchanged for
  non-retryable canceled stream failures.

### Deliverables

- Runtime stream retry matrix tests covering canceled non-retryable
  classification and telemetry invariants.

### Exit criteria

- Canceled stream runtime failures are classified deterministically and never
  retried across both built-in adapters.

### Completion notes

- Extended stream retry policy matrix with canceled non-retryable coverage:
  - `test/jido_conversation/runtime/llm_retry_policy_stream_matrix_test.exs`
- Added explicit assertions for:
  - no retry attempts on canceled-classified stream failures
  - failed stream lifecycle payload category/retryable invariants
    (`canceled`, `false`)
  - no `canceled` retry counter increments in telemetry snapshot for stream
    paths

## Phase 27: Provider non-retryable runtime parity hardening

### Objectives

- Harden non-stream provider `4xx` non-retryable runtime parity assertions for
  built-in adapters.
- Ensure failed lifecycle payload invariants are explicitly verified for the
  provider category.

### Tasks

- Update non-stream runtime retry matrix provider `4xx` coverage for:
  - `jido_ai` backend path (`422` provider validation failure)
  - `harness` backend path (`422` provider validation failure)
- Assert failed lifecycle payload includes:
  - `error_category: "provider"`
  - `retryable?: false`
- Preserve invariant that provider retry category counters do not increment for
  non-retryable provider failures.

### Deliverables

- Updated non-stream runtime retry matrix tests for provider non-retryable
  classification parity and telemetry invariants.

### Exit criteria

- Provider `4xx` non-stream runtime failures for both built-in adapters verify
  deterministic failed payload classification (`provider`, non-retryable) and
  no retry category counter increments.

### Completion notes

- Hardened provider `4xx` non-retryable runtime tests to assert failed payload
  category/retryable invariants:
  - `test/jido_conversation/runtime/llm_retry_policy_matrix_test.exs`
- Unified provider non-retryable assertions with retry-category helper
  patterns used by later phase slices.

## Phase 28: Stream provider non-retryable runtime parity hardening

### Objectives

- Harden stream provider `4xx` non-retryable runtime parity assertions for
  built-in adapters.
- Ensure failed stream lifecycle payload invariants are explicitly verified for
  the provider category.

### Tasks

- Update stream runtime retry matrix provider `4xx` coverage for:
  - `jido_ai` backend stream path (`422` provider validation failure)
  - `harness` backend stream path (`422` provider validation failure)
- Assert failed stream lifecycle payload includes:
  - `error_category: "provider"`
  - `retryable?: false`
- Preserve invariant that provider retry category counters do not increment for
  non-retryable provider stream failures.

### Deliverables

- Updated stream runtime retry matrix tests for provider non-retryable
  classification parity and telemetry invariants.

### Exit criteria

- Provider `4xx` stream runtime failures for both built-in adapters verify
  deterministic failed payload classification (`provider`, non-retryable) and
  no retry category counter increments.

### Completion notes

- Hardened provider `4xx` non-retryable stream runtime tests to assert failed
  payload category/retryable invariants:
  - `test/jido_conversation/runtime/llm_retry_policy_stream_matrix_test.exs`
- Unified stream provider non-retryable assertions with retry-category helper
  patterns used by adjacent phase slices.

## Phase 29: Non-stream retry progress payload parity hardening

### Objectives

- Harden non-stream retry-path payload parity assertions for built-in adapters.
- Ensure retrying progress lifecycle payload explicitly carries expected retry
  category and retryable classification across retryable categories.

### Tasks

- Update non-stream runtime retry matrix retry-path coverage to assert retrying
  progress payload invariants for:
  - provider retryable recovery path (`retryable_then_success`)
  - timeout retryable recovery path (`timeout_then_success`)
  - transport retryable recovery path (`transport_then_success`)
- Assert retrying progress payload includes:
  - `status: "retrying"`
  - `error_category: <expected category>`
  - `retryable?: true`
- Keep terminal completion and retry telemetry increment assertions unchanged.

### Deliverables

- Updated non-stream runtime retry matrix helper assertions and retryable
  provider-path tests.

### Exit criteria

- Non-stream retryable runtime paths across both built-in adapters verify
  deterministic retrying progress payload classification and retry category
  telemetry increments.

### Completion notes

- Updated runtime retrying lifecycle payload emission for LLM effects to include
  normalized `error_category`:
  - `lib/jido_conversation/runtime/effect_worker.ex`
- Hardened non-stream retry helper assertions to validate retrying progress
  payload category/retryable invariants:
  - `test/jido_conversation/runtime/llm_retry_policy_matrix_test.exs`
- Refactored non-stream provider retryable recovery tests to use the shared
  retry-category helper path for consistent parity checks.

## Phase 30: Stream retry progress payload parity hardening

### Objectives

- Harden stream retry-path payload parity assertions for built-in adapters.
- Ensure retrying stream progress lifecycle payload explicitly carries expected
  retry category and retryable classification across retryable categories.

### Tasks

- Update stream runtime retry matrix retry-path coverage to assert retrying
  progress payload invariants for:
  - provider retryable recovery path (`retryable_then_success`)
  - timeout retryable recovery path (`timeout_then_success`)
  - transport retryable recovery path (`transport_then_success`)
- Assert retrying stream progress payload includes:
  - `status: "retrying"`
  - `error_category: <expected category>`
  - `retryable?: true`
- Keep terminal completion and retry telemetry increment assertions unchanged.

### Deliverables

- Updated stream runtime retry matrix helper assertions and retryable provider
  path tests.

### Exit criteria

- Stream retryable runtime paths across both built-in adapters verify
  deterministic retrying progress payload classification and retry category
  telemetry increments.

### Completion notes

- Hardened stream retry helper assertions to validate retrying progress payload
  category/retryable invariants:
  - `test/jido_conversation/runtime/llm_retry_policy_stream_matrix_test.exs`
- Refactored stream provider retryable recovery tests to use the shared
  retry-category helper path for consistent parity checks.

## Phase 31: Telemetry retry-category parity hardening

### Objectives

- Harden retry-category aggregation invariants in telemetry snapshot handling.
- Ensure retry-category precedence and fallback behavior remains deterministic.

### Tasks

- Extend telemetry test coverage for runtime LLM retry events to verify:
  - explicit `retry_category` increments the matching counter
  - missing `retry_category` falls back to `error_category`
  - when both are present, `retry_category` takes precedence
  - blank retry category values are ignored

### Deliverables

- Added telemetry unit coverage for retry-category precedence/fallback rules.

### Exit criteria

- Telemetry snapshot `llm.retry_by_category` reflects deterministic increments
  for explicit and fallback categories without double-counting conflicting
  metadata.

### Completion notes

- Added retry-category precedence/fallback parity test:
  - `test/jido_conversation/telemetry_test.exs`

## Phase 32: Effect-manager LLM retry lifecycle parity hardening

### Objectives

- Harden lower-level effect runtime coverage for LLM retry classification.
- Ensure effect manager integration tests assert retrying lifecycle payload
  classification invariants directly.

### Tasks

- Add retryable LLM backend stub behavior in effect manager tests:
  - first attempt returns retryable provider error
  - second attempt recovers with completion
- Assert retrying lifecycle payload includes:
  - `status: "retrying"`
  - `error_category: "provider"`
  - `retryable?: true`
- Assert provider retry-category telemetry increments exactly once for the
  recovery path.

### Deliverables

- Extended effect manager runtime coverage for retrying LLM lifecycle payload
  classification and retry telemetry invariants.

### Exit criteria

- Effect runtime integration tests verify retrying payload classification
  consistency and provider retry telemetry behavior for retryable LLM failures.

### Completion notes

- Added retryable provider backend stub and recovery assertions in:
  - `test/jido_conversation/runtime/effect_manager_test.exs`

## Phase 33: Effect-manager LLM start-path retry parity hardening

### Objectives

- Extend effect runtime retry classification parity coverage to non-stream LLM
  execution (`start/2`) paths.
- Ensure retrying lifecycle payload invariants remain consistent between stream
  and non-stream backend execution modes.

### Tasks

- Add non-stream effect manager retry test for retryable provider errors:
  - first non-stream attempt returns retryable provider error
  - second non-stream attempt recovers with completion
- Assert retrying lifecycle payload includes:
  - `status: "retrying"`
  - `error_category: "provider"`
  - `retryable?: true`
- Assert provider retry-category telemetry increments exactly once for the
  non-stream recovery path.

### Deliverables

- Extended effect manager runtime tests for non-stream LLM retry lifecycle
  payload classification and telemetry invariants.

### Exit criteria

- Effect runtime integration tests verify parity of retrying payload
  classification and retry telemetry behavior across stream and non-stream LLM
  backend execution paths.

### Completion notes

- Added non-stream retryable provider recovery assertions and stream-mode test
  helper override in:
  - `test/jido_conversation/runtime/effect_manager_test.exs`

## Phase 34: Effect-manager LLM start-path non-retry parity hardening

### Objectives

- Extend effect runtime non-retryable parity coverage to non-stream LLM
  execution (`start/2`) paths.
- Ensure non-stream non-retryable failures preserve failed payload
  classification and do not increment retry counters.

### Tasks

- Add non-stream effect manager test for non-retryable config errors:
  - first non-stream attempt returns non-retryable config error
  - no subsequent attempts are started even when `max_attempts > 1`
- Assert failed lifecycle payload includes:
  - `error_category: "config"`
  - `retryable?: false`
- Assert no retrying progress lifecycle is emitted.
- Assert telemetry retry category `config` remains unchanged.

### Deliverables

- Extended effect manager runtime tests for non-stream non-retryable LLM failed
  payload classification and retry telemetry invariants.

### Exit criteria

- Effect runtime integration tests verify deterministic non-stream non-retryable
  failed payload classification and no retry-category increments for config
  failures.

### Completion notes

- Added non-stream non-retryable config failure assertions in:
  - `test/jido_conversation/runtime/effect_manager_test.exs`

## Phase 35: Effect-manager LLM stream-path non-retry parity hardening

### Objectives

- Harden effect runtime non-retryable parity coverage for stream-path LLM
  execution.
- Ensure stream-path non-retryable failures carry deterministic failed payload
  classification and do not increment retry counters.

### Tasks

- Extend stream-path effect manager test for non-retryable config errors to
  assert:
  - no second stream attempt occurs with `max_attempts > 1`
  - failed payload includes `error_category: "config"` and `retryable?: false`
  - no retrying progress lifecycle is emitted
  - telemetry retry category `config` remains unchanged

### Deliverables

- Hardened stream-path effect manager non-retryable LLM test assertions for
  failed payload classification and retry telemetry invariants.

### Exit criteria

- Effect runtime integration tests verify deterministic stream non-retryable
  failed payload classification and no retry-category increments for config
  failures.

### Completion notes

- Extended stream non-retryable config failure assertions in:
  - `test/jido_conversation/runtime/effect_manager_test.exs`

## Phase 36: Effect-manager LLM stream-path retry cardinality parity hardening

### Objectives

- Harden effect runtime retryable stream-path parity coverage for deterministic
  attempt bounds and lifecycle cardinality.
- Ensure successful retry recovery does not regress failed lifecycle telemetry.

### Tasks

- Extend retryable stream-path effect manager test to assert:
  - stream retries stop at the expected bound for a single retryable failure
  - exactly one retrying progress lifecycle is emitted
  - started/completed lifecycle cardinality remains deterministic
  - failed lifecycle telemetry does not increment on successful recovery

### Deliverables

- Hardened stream retry-path effect manager test assertions for attempt
  cardinality, retrying lifecycle cardinality, and failed telemetry invariants.

### Exit criteria

- Effect runtime integration tests verify deterministic stream retry attempt
  bounds and no failed-telemetry regression when retryable failures recover.

### Completion notes

- Extended stream retryable provider failure assertions in:
  - `test/jido_conversation/runtime/effect_manager_test.exs`

## Phase 37: Effect-manager LLM start-path retry cardinality parity hardening

### Objectives

- Harden effect runtime retryable start-path parity coverage for deterministic
  attempt bounds and lifecycle cardinality.
- Ensure successful non-stream retry recovery does not regress failed lifecycle
  telemetry.

### Tasks

- Extend retryable start-path effect manager test to assert:
  - non-stream retries stop at the expected bound for a single retryable failure
  - exactly one retrying progress lifecycle is emitted
  - started/completed lifecycle cardinality remains deterministic
  - failed lifecycle telemetry does not increment on successful recovery

### Deliverables

- Hardened start-path retry effect manager test assertions for attempt
  cardinality, retrying lifecycle cardinality, and failed telemetry invariants.

### Exit criteria

- Effect runtime integration tests verify deterministic non-stream retry attempt
  bounds and no failed-telemetry regression when retryable failures recover.

### Completion notes

- Extended non-stream retryable provider failure assertions in:
  - `test/jido_conversation/runtime/effect_manager_test.exs`

## Phase 38: Effect-manager LLM stream-path retry-attempt-start parity hardening

### Objectives

- Harden effect runtime retryable stream-path parity coverage for deterministic
  retry-attempt-start lifecycle semantics.
- Ensure the retry-attempt-start progress lifecycle is emitted exactly once and
  with the expected attempt number.

### Tasks

- Extend retryable stream-path effect manager test to assert:
  - a `retry_attempt_started` progress lifecycle is emitted
  - `retry_attempt_started` carries `attempt: 2` for single retry recovery
  - `retry_attempt_started` lifecycle cardinality is exactly one

### Deliverables

- Hardened stream retry-path effect manager test assertions for
  retry-attempt-start lifecycle cardinality and attempt labeling invariants.

### Exit criteria

- Effect runtime integration tests verify deterministic stream
  retry-attempt-start lifecycle payload semantics and cardinality for retryable
  recovery.

### Completion notes

- Extended stream retryable provider failure assertions in:
  - `test/jido_conversation/runtime/effect_manager_test.exs`

## Phase 39: Effect-manager LLM start-path retry-attempt-start parity hardening

### Objectives

- Harden effect runtime retryable start-path parity coverage for deterministic
  retry-attempt-start lifecycle semantics.
- Ensure the non-stream retry-attempt-start progress lifecycle is emitted
  exactly once and with the expected attempt number.

### Tasks

- Extend retryable start-path effect manager test to assert:
  - a `retry_attempt_started` progress lifecycle is emitted
  - `retry_attempt_started` carries `attempt: 2` for single retry recovery
  - `retry_attempt_started` lifecycle cardinality is exactly one

### Deliverables

- Hardened start-path retry effect manager test assertions for
  retry-attempt-start lifecycle cardinality and attempt labeling invariants.

### Exit criteria

- Effect runtime integration tests verify deterministic non-stream
  retry-attempt-start lifecycle payload semantics and cardinality for retryable
  recovery.

### Completion notes

- Extended non-stream retryable provider failure assertions in:
  - `test/jido_conversation/runtime/effect_manager_test.exs`

## Phase 40: Effect-manager LLM cancel lifecycle/telemetry parity hardening

### Objectives

- Harden effect runtime LLM cancellation parity coverage for deterministic
  canceled lifecycle payload/cardinality semantics.
- Ensure cancellation updates runtime telemetry snapshot consistently without
  introducing retry-category regressions.

### Tasks

- Extend effect manager cancellation test to assert:
  - backend cancellation is invoked with the captured execution reference
  - exactly one `started` and one `canceled` lifecycle is emitted
  - no `completed` or `failed` lifecycle is emitted after cancellation
  - canceled payload includes `reason: "user_abort"` and `backend_cancel: "ok"`
  - telemetry `lifecycle_counts.canceled` and `cancel_results["ok"]` increment
  - retry-category telemetry remains unchanged

### Deliverables

- Hardened effect manager cancellation test assertions for canceled lifecycle
  payload/cardinality and cancel telemetry snapshot invariants.

### Exit criteria

- Effect runtime integration tests verify deterministic cancellation lifecycle
  semantics and consistent cancel telemetry updates without retry drift.

### Completion notes

- Extended cancellation-path assertions in:
  - `test/jido_conversation/runtime/effect_manager_test.exs`

## Phase 41: Effect-manager LLM cancel-without-context parity hardening

### Objectives

- Harden effect runtime LLM cancellation parity coverage when no backend
  execution reference is available.
- Ensure canceled lifecycle payload and telemetry remain deterministic for the
  no-context cancellation path.

### Tasks

- Extend cancellable backend test scaffolding to support stream events without
  `execution_ref` metadata.
- Add effect manager cancellation test for missing `execution_ref` to assert:
  - backend cancel is not invoked
  - exactly one `started` and one `canceled` lifecycle is emitted
  - no `completed` or `failed` lifecycle is emitted
  - canceled payload includes `reason: "user_abort"` and
    `backend_cancel: "not_available"`
  - telemetry `lifecycle_counts.canceled`, `cancel_latency_ms.count`, and
    `cancel_results["not_available"]` increment
  - retry-category telemetry remains unchanged

### Deliverables

- Hardened effect manager cancellation test assertions for no-context cancel
  lifecycle payload/cardinality and cancel telemetry snapshot invariants.

### Exit criteria

- Effect runtime integration tests verify deterministic no-context cancellation
  lifecycle semantics and consistent `not_available` cancel telemetry updates
  without retry drift.

### Completion notes

- Extended no-context cancellation assertions and backend stub options in:
  - `test/jido_conversation/runtime/effect_manager_test.exs`

## Phase 42: Effect-manager LLM cancel-failed parity hardening

### Objectives

- Harden effect runtime LLM cancellation parity coverage when backend
  cancellation returns an error.
- Ensure canceled lifecycle payload and telemetry remain deterministic for the
  cancel-failed path.

### Tasks

- Extend cancellable backend test scaffolding to support configurable
  cancellation failure responses.
- Add effect manager cancellation test for backend cancel failure to assert:
  - backend cancel is invoked with captured execution reference
  - exactly one `started` and one `canceled` lifecycle is emitted
  - no `completed` or `failed` lifecycle is emitted
  - canceled payload includes `reason: "user_abort"` and
    `backend_cancel: "failed"`
  - canceled payload includes backend cancel error fields (`reason`, `category`,
    `retryable?`)
  - telemetry `lifecycle_counts.canceled`, `cancel_latency_ms.count`, and
    `cancel_results["failed"]` increment
  - retry-category telemetry remains unchanged

### Deliverables

- Hardened effect manager cancellation test assertions for failed-backend cancel
  lifecycle payload/cardinality and cancel telemetry snapshot invariants.

### Exit criteria

- Effect runtime integration tests verify deterministic cancel-failed lifecycle
  semantics and consistent `failed` cancel telemetry updates without retry
  drift.

### Completion notes

- Extended cancel-failed cancellation assertions and backend stub options in:
  - `test/jido_conversation/runtime/effect_manager_test.exs`

## Phase 43: Effect-manager LLM cancel attribution parity hardening

### Objectives

- Harden effect runtime LLM cancellation parity coverage for attribution fields
  in cancel-failed lifecycle payloads.
- Ensure backend lifecycle telemetry attribution remains consistent for
  cancel-failed outcomes.

### Tasks

- Extend effect manager cancel-failed test to assert canceled payload includes:
  - `backend: "jido_ai"`
  - `provider: "stub-provider"`
  - `model: "stub-model"`
- Assert backend lifecycle telemetry reflects canceled increments for the
  resolved backend key (`"jido_ai"`).

### Deliverables

- Hardened cancel-failed effect manager assertions for lifecycle attribution
  payload and backend lifecycle telemetry invariants.

### Exit criteria

- Effect runtime integration tests verify deterministic cancel-failed attribution
  payload fields and backend canceled lifecycle telemetry increments.

### Completion notes

- Extended cancel-failed attribution and backend lifecycle telemetry assertions
  in:
  - `test/jido_conversation/runtime/effect_manager_test.exs`

## Phase 44: Effect-manager LLM cancel cause-link parity hardening

### Objectives

- Harden effect runtime LLM cancellation parity coverage for explicit
  `cause_id` linkage on canceled lifecycle emission.
- Ensure canceled lifecycle records are traceable back to the provided cancel
  cause through journal chain traversal.

### Tasks

- Add effect manager cancellation test with explicit valid `cause_id` to assert:
  - cancellation still invokes backend cancel path
  - canceled lifecycle is emitted for the target effect
  - backward trace chain from canceled lifecycle includes:
    - canceled lifecycle signal id
    - explicit cancel cause signal id

### Deliverables

- Hardened effect manager cancellation test assertions for explicit cancel
  cause-link lifecycle tracing invariants.

### Exit criteria

- Effect runtime integration tests verify deterministic canceled lifecycle
  linkage to provided cancel causes and backward trace-chain integrity.

### Completion notes

- Added explicit cancel cause-link tracing assertions in:
  - `test/jido_conversation/runtime/effect_manager_test.exs`

## Phase 45: Effect-manager LLM cancel invalid-cause fallback parity hardening

### Objectives

- Harden effect runtime LLM cancellation parity coverage for invalid explicit
  cancel `cause_id` values.
- Ensure canceled lifecycle ingestion falls back to uncoupled trace linkage
  while preserving cancel telemetry invariants.

### Tasks

- Add effect manager cancellation test with invalid explicit `cause_id` to
  assert:
  - backend cancel path remains invoked
  - canceled lifecycle is emitted for the target effect
  - backward trace chain from canceled lifecycle includes canceled signal id
  - backward trace chain does not include invalid cancel `cause_id`
  - telemetry `lifecycle_counts.canceled` and `cancel_results["ok"]` increment
  - retry-category telemetry remains unchanged

### Deliverables

- Hardened effect manager cancellation test assertions for invalid cancel
  cause fallback lifecycle tracing and cancel telemetry invariants.

### Exit criteria

- Effect runtime integration tests verify deterministic invalid-cause fallback
  tracing semantics and consistent cancel telemetry updates without retry drift.

### Completion notes

- Added invalid cancel cause fallback tracing assertions in:
  - `test/jido_conversation/runtime/effect_manager_test.exs`

## Phase 46: Effect-manager LLM cancel-failed cause-link parity hardening

### Objectives

- Harden effect runtime LLM cancellation parity coverage for explicit
  `cause_id` linkage when backend cancellation returns failure.
- Ensure failed-cancel lifecycle records remain traceable to explicit cancel
  causes while preserving cancel telemetry invariants.

### Tasks

- Add effect manager cancellation test for failed backend cancel with explicit
  `cause_id` to assert:
  - backend cancel failure path remains invoked
  - canceled lifecycle is emitted for the target effect with
    `backend_cancel: "failed"`
  - backward trace chain from canceled lifecycle includes:
    - canceled lifecycle signal id
    - explicit cancel cause signal id
  - telemetry `lifecycle_counts.canceled` and `cancel_results["failed"]`
    increment
  - retry-category telemetry remains unchanged

### Deliverables

- Hardened effect manager cancellation test assertions for failed-cancel
  explicit cause-link tracing and cancel telemetry invariants.

### Exit criteria

- Effect runtime integration tests verify deterministic explicit cause linkage
  for failed-cancel lifecycle events and consistent failed-cancel telemetry
  updates without retry drift.

### Completion notes

- Added failed-cancel explicit cause-link tracing assertions in:
  - `test/jido_conversation/runtime/effect_manager_test.exs`

## Phase 47: Effect-manager LLM cancel-failed invalid-cause fallback parity hardening

### Objectives

- Harden effect runtime LLM cancellation parity coverage for invalid explicit
  `cause_id` values when backend cancellation returns failure.
- Ensure canceled lifecycle ingestion falls back to uncoupled trace linkage
  while preserving failed-cancel telemetry invariants.

### Tasks

- Add effect manager cancellation test for failed backend cancel with invalid
  explicit `cause_id` to assert:
  - backend cancel failure path remains invoked
  - canceled lifecycle is emitted for the target effect with
    `backend_cancel: "failed"`
  - backward trace chain from canceled lifecycle includes canceled signal id
  - backward trace chain does not include invalid cancel `cause_id`
  - telemetry `lifecycle_counts.canceled` and `cancel_results["failed"]`
    increment
  - retry-category telemetry remains unchanged

### Deliverables

- Hardened effect manager cancellation test assertions for failed-cancel
  invalid cause fallback tracing and cancel telemetry invariants.

### Exit criteria

- Effect runtime integration tests verify deterministic invalid-cause fallback
  tracing semantics for failed-cancel lifecycle events and consistent
  failed-cancel telemetry updates without retry drift.

### Completion notes

- Added failed-cancel invalid cause fallback tracing assertions in:
  - `test/jido_conversation/runtime/effect_manager_test.exs`

## Phase 48: Effect-manager LLM cancel-failed invalid-cause attribution parity hardening

### Objectives

- Harden effect runtime LLM cancellation parity coverage for attribution and
  cancel-error category fields in invalid explicit `cause_id` failed-cancel
  scenarios.
- Ensure backend lifecycle telemetry attribution remains consistent for
  failed-cancel invalid-cause fallback outcomes.

### Tasks

- Extend effect manager failed-cancel invalid-cause test to assert canceled
  payload includes:
  - `backend_cancel_category: "provider"`
  - `backend_cancel_retryable?: true`
  - `backend: "jido_ai"`
  - `provider: "stub-provider"`
  - `model: "stub-model"`
- Assert backend lifecycle telemetry reflects canceled increments for the
  resolved backend key (`"jido_ai"`).

### Deliverables

- Hardened failed-cancel invalid-cause effect manager assertions for
  attribution/category payload fields and backend lifecycle telemetry
  invariants.

### Exit criteria

- Effect runtime integration tests verify deterministic failed-cancel
  invalid-cause attribution/category payload fields and backend canceled
  lifecycle telemetry increments.

### Completion notes

- Extended failed-cancel invalid-cause attribution/category and backend
  lifecycle telemetry assertions in:
  - `test/jido_conversation/runtime/effect_manager_test.exs`

## Phase 49: Cancel-failed invalid-cause fallback matrix parity hardening

### Objectives

- Harden runtime cancellation parity coverage for failed backend cancellation
  with invalid explicit `cause_id` values across both built-in backends.
- Ensure uncoupled trace fallback and failed-cancel telemetry/back-end
  attribution invariants hold consistently for `jido_ai` and `harness`.

### Tasks

- Add runtime matrix coverage for failed-cancel invalid `cause_id` fallback
  across `[:jido_ai, :harness]` to assert:
  - backend cancel failure path remains invoked
  - canceled lifecycle payload includes failed-cancel error metadata
  - canceled lifecycle payload includes backend/provider/model attribution per
    backend config
  - backward trace chain includes canceled signal id and excludes invalid
    `cause_id`
  - telemetry `lifecycle_counts.canceled`, `cancel_latency_ms.count`, and
    `cancel_results["failed"]` increment
  - backend lifecycle telemetry increments for the resolved backend key
  - retry-category telemetry remains unchanged

### Deliverables

- Hardened cancel telemetry matrix coverage for cross-backend failed-cancel
  invalid-cause fallback tracing and telemetry attribution invariants.

### Exit criteria

- Runtime matrix tests verify deterministic invalid-cause fallback tracing
  semantics and failed-cancel telemetry/back-end attribution parity across
  `jido_ai` and `harness`.

### Completion notes

- Added cross-backend failed-cancel invalid cause fallback tracing and
  telemetry attribution assertions in:
  - `test/jido_conversation/runtime/llm_cancel_telemetry_matrix_test.exs`

## Phase 50: Cancel-failed cause-link matrix parity hardening

### Objectives

- Harden runtime cancellation parity coverage for failed backend cancellation
  with explicit valid `cause_id` values across both built-in backends.
- Ensure failed-cancel lifecycle records remain traceable to explicit causes
  while preserving failed-cancel telemetry and backend attribution invariants
  for `jido_ai` and `harness`.

### Tasks

- Add runtime matrix coverage for failed-cancel explicit `cause_id` linkage
  across `[:jido_ai, :harness]` to assert:
  - backend cancel failure path remains invoked
  - canceled lifecycle payload includes failed-cancel error metadata
  - canceled lifecycle payload includes backend/provider/model attribution per
    backend config
  - backward trace chain includes canceled signal id and explicit cause signal
    id
  - telemetry `lifecycle_counts.canceled`, `cancel_latency_ms.count`, and
    `cancel_results["failed"]` increment
  - backend lifecycle telemetry increments for the resolved backend key
  - retry-category telemetry remains unchanged

### Deliverables

- Hardened cancel telemetry matrix coverage for cross-backend failed-cancel
  explicit cause-link tracing and telemetry attribution invariants.

### Exit criteria

- Runtime matrix tests verify deterministic explicit cause linkage semantics
  and failed-cancel telemetry/back-end attribution parity across `jido_ai` and
  `harness`.

### Completion notes

- Added cross-backend failed-cancel explicit cause-link tracing and telemetry
  attribution assertions in:
  - `test/jido_conversation/runtime/llm_cancel_telemetry_matrix_test.exs`

## Phase 51: Cancel-ok cause-link matrix parity hardening

### Objectives

- Harden runtime cancellation parity coverage for successful backend
  cancellation with explicit valid `cause_id` values across built-in backends.
- Ensure canceled lifecycle records remain traceable to explicit causes while
  preserving cancel-ok telemetry and backend lifecycle invariants for
  `jido_ai` and `harness`.

### Tasks

- Add runtime matrix coverage for cancel-ok explicit `cause_id` linkage across
  `[:jido_ai, :harness]` to assert:
  - backend cancel path remains invoked with `:ok` result
  - canceled lifecycle payload includes `backend_cancel: "ok"` and cancel
    reason metadata
  - backward trace chain includes canceled signal id and explicit cause signal
    id
  - telemetry `lifecycle_counts.canceled`, `cancel_latency_ms.count`, and
    `cancel_results["ok"]` increment
  - backend lifecycle telemetry increments for the resolved backend key
  - retry-category telemetry remains unchanged

### Deliverables

- Hardened cancel telemetry matrix coverage for cross-backend cancel-ok
  explicit cause-link tracing and telemetry invariants.

### Exit criteria

- Runtime matrix tests verify deterministic explicit cause linkage semantics
  and cancel-ok telemetry/back-end lifecycle parity across `jido_ai` and
  `harness`.

### Completion notes

- Added cross-backend cancel-ok explicit cause-link tracing and telemetry
  assertions in:
  - `test/jido_conversation/runtime/llm_cancel_telemetry_matrix_test.exs`

## Phase 52: Cancel-ok invalid-cause fallback matrix parity hardening

### Objectives

- Harden runtime cancellation parity coverage for successful backend
  cancellation with invalid explicit `cause_id` values across built-in
  backends.
- Ensure uncoupled trace fallback semantics while preserving cancel-ok
  telemetry and backend attribution/lifecycle invariants for `jido_ai` and
  `harness`.

### Tasks

- Add runtime matrix coverage for cancel-ok invalid `cause_id` fallback across
  `[:jido_ai, :harness]` to assert:
  - backend cancel path remains invoked with `:ok` result
  - canceled lifecycle payload includes `backend_cancel: "ok"` and
    backend/provider/model attribution per backend config
  - backward trace chain includes canceled signal id and excludes invalid
    `cause_id`
  - telemetry `lifecycle_counts.canceled`, `cancel_latency_ms.count`, and
    `cancel_results["ok"]` increment
  - backend lifecycle telemetry increments for the resolved backend key
  - retry-category telemetry remains unchanged

### Deliverables

- Hardened cancel telemetry matrix coverage for cross-backend cancel-ok
  invalid-cause fallback tracing and telemetry invariants.

### Exit criteria

- Runtime matrix tests verify deterministic invalid-cause fallback semantics
  and cancel-ok telemetry/back-end lifecycle attribution parity across
  `jido_ai` and `harness`.

### Completion notes

- Added cross-backend cancel-ok invalid cause fallback tracing and telemetry
  attribution assertions in:
  - `test/jido_conversation/runtime/llm_cancel_telemetry_matrix_test.exs`

## Phase 53: Cancel-not-available invalid-cause fallback matrix parity hardening

### Objectives

- Harden runtime cancellation parity coverage for not-available backend cancel
  outcomes (missing execution ref) with invalid explicit `cause_id` values
  across built-in backends.
- Ensure uncoupled trace fallback semantics while preserving
  cancel-not-available telemetry and backend attribution/lifecycle invariants
  for `jido_ai` and `harness`.

### Tasks

- Add runtime matrix coverage for cancel-not-available invalid `cause_id`
  fallback across `[:jido_ai, :harness]` to assert:
  - backend cancel callback is not invoked
  - canceled lifecycle payload includes `backend_cancel: "not_available"` and
    backend/provider/model attribution per backend config
  - backward trace chain includes canceled signal id and excludes invalid
    `cause_id`
  - telemetry `lifecycle_counts.canceled`, `cancel_latency_ms.count`, and
    `cancel_results["not_available"]` increment
  - backend lifecycle telemetry increments for the resolved backend key
  - retry-category telemetry remains unchanged

### Deliverables

- Hardened cancel telemetry matrix coverage for cross-backend
  cancel-not-available invalid-cause fallback tracing and telemetry
  invariants.

### Exit criteria

- Runtime matrix tests verify deterministic invalid-cause fallback semantics
  for cancel-not-available outcomes and telemetry/back-end lifecycle
  attribution parity across `jido_ai` and `harness`.

### Completion notes

- Added cross-backend cancel-not-available invalid cause fallback tracing and
  telemetry attribution assertions in:
  - `test/jido_conversation/runtime/llm_cancel_telemetry_matrix_test.exs`

## Phase 54: Cancel-not-available cause-link matrix parity hardening

### Objectives

- Harden runtime cancellation parity coverage for not-available backend cancel
  outcomes (missing execution ref) with explicit valid `cause_id` values
  across built-in backends.
- Ensure canceled lifecycle records remain traceable to explicit causes while
  preserving cancel-not-available telemetry and backend attribution/lifecycle
  invariants for `jido_ai` and `harness`.

### Tasks

- Add runtime matrix coverage for cancel-not-available explicit `cause_id`
  linkage across `[:jido_ai, :harness]` to assert:
  - backend cancel callback is not invoked
  - canceled lifecycle payload includes `backend_cancel: "not_available"` and
    backend/provider/model attribution per backend config
  - backward trace chain includes canceled signal id and explicit cause signal
    id
  - telemetry `lifecycle_counts.canceled`, `cancel_latency_ms.count`, and
    `cancel_results["not_available"]` increment
  - backend lifecycle telemetry increments for the resolved backend key
  - retry-category telemetry remains unchanged

### Deliverables

- Hardened cancel telemetry matrix coverage for cross-backend
  cancel-not-available explicit cause-link tracing and telemetry invariants.

### Exit criteria

- Runtime matrix tests verify deterministic explicit cause-link semantics for
  cancel-not-available outcomes and telemetry/back-end lifecycle attribution
  parity across `jido_ai` and `harness`.

### Completion notes

- Added cross-backend cancel-not-available explicit cause-link tracing and
  telemetry attribution assertions in:
  - `test/jido_conversation/runtime/llm_cancel_telemetry_matrix_test.exs`

## Phase 55: Cancel-not-available baseline attribution matrix parity hardening

### Objectives

- Harden baseline runtime cancellation parity coverage for not-available
  backend cancel outcomes (missing execution ref) across built-in backends.
- Ensure baseline cancel-not-available assertions include lifecycle payload
  attribution and backend lifecycle telemetry invariants in addition to cancel
  result counters.

### Tasks

- Extend baseline cancel-not-available matrix test across
  `[:jido_ai, :harness]` to assert:
  - canceled lifecycle payload includes:
    - `reason: "user_abort"`
    - `backend_cancel: "not_available"`
    - backend/provider/model attribution per backend config
  - telemetry `lifecycle_counts.canceled`, `cancel_latency_ms.count`, and
    `cancel_results["not_available"]` increment
  - backend lifecycle telemetry increments for the resolved backend key
  - retry-category telemetry remains unchanged

### Deliverables

- Hardened baseline cancel-not-available matrix assertions for payload
  attribution and backend lifecycle telemetry invariants.

### Exit criteria

- Runtime matrix tests verify deterministic baseline cancel-not-available
  payload attribution and telemetry/back-end lifecycle parity across
  `jido_ai` and `harness`.

### Completion notes

- Extended baseline cancel-not-available payload attribution and backend
  lifecycle telemetry assertions in:
  - `test/jido_conversation/runtime/llm_cancel_telemetry_matrix_test.exs`

## Phase 56: Cancel-failed baseline attribution matrix parity hardening

### Objectives

- Harden baseline runtime cancellation parity coverage for failed backend
  cancellation outcomes across built-in backends.
- Ensure baseline cancel-failed assertions include lifecycle payload
  attribution/error metadata and backend lifecycle telemetry invariants in
  addition to cancel result counters.

### Tasks

- Extend baseline cancel-failed matrix test across `[:jido_ai, :harness]` to
  assert canceled lifecycle payload includes:
  - `reason: "user_abort"`
  - `backend_cancel: "failed"`
  - `backend_cancel_reason: "cancel failed"`
  - `backend_cancel_category: "provider"`
  - `backend_cancel_retryable?: true`
  - backend/provider/model attribution per backend config
- Assert telemetry:
  - `lifecycle_counts.canceled`, `cancel_latency_ms.count`, and
    `cancel_results["failed"]` increment
  - backend lifecycle telemetry increments for the resolved backend key
  - retry-category telemetry remains unchanged

### Deliverables

- Hardened baseline cancel-failed matrix assertions for payload
  attribution/error metadata and backend lifecycle telemetry invariants.

### Exit criteria

- Runtime matrix tests verify deterministic baseline cancel-failed payload
  attribution/error metadata and telemetry/back-end lifecycle parity across
  `jido_ai` and `harness`.

### Completion notes

- Extended baseline cancel-failed payload attribution/error metadata and
  backend lifecycle telemetry assertions in:
  - `test/jido_conversation/runtime/llm_cancel_telemetry_matrix_test.exs`

## Phase 57: Cancel-ok baseline attribution matrix parity hardening

### Objectives

- Harden baseline runtime cancellation parity coverage for successful backend
  cancellation outcomes across built-in backends.
- Ensure baseline cancel-ok assertions include lifecycle payload attribution
  and retry-category telemetry invariants in addition to cancel result and
  backend lifecycle counters.

### Tasks

- Extend baseline cancel-ok matrix test across `[:jido_ai, :harness]` to
  assert canceled lifecycle payload includes:
  - `reason: "user_abort"`
  - `backend_cancel: "ok"`
  - backend/provider/model attribution per backend config
- Assert telemetry:
  - `lifecycle_counts.canceled`, `cancel_latency_ms.count`, and
    `cancel_results["ok"]` increment
  - backend lifecycle telemetry increments for the resolved backend key
  - retry-category telemetry remains unchanged

### Deliverables

- Hardened baseline cancel-ok matrix assertions for payload attribution and
  backend lifecycle/retry-category telemetry invariants.

### Exit criteria

- Runtime matrix tests verify deterministic baseline cancel-ok payload
  attribution and telemetry/back-end lifecycle parity across `jido_ai` and
  `harness`.

### Completion notes

- Extended baseline cancel-ok payload attribution and backend lifecycle/
  retry-category telemetry assertions in:
  - `test/jido_conversation/runtime/llm_cancel_telemetry_matrix_test.exs`

## Phase 58: Cancel baseline terminal-exclusivity matrix parity hardening

### Objectives

- Harden baseline runtime cancellation parity coverage by enforcing terminal
  lifecycle exclusivity semantics across built-in backends.
- Ensure baseline cancel scenarios emit exactly one terminal `canceled`
  lifecycle and never regress to `completed` or `failed` terminal events for
  the same effect.

### Tasks

- Add shared terminal-exclusivity assertion helper in cancel telemetry matrix
  tests to validate:
  - exactly one `canceled` terminal lifecycle for target effect
  - no terminal `completed`
  - no terminal `failed`
- Apply helper to baseline matrix scenarios across `[:jido_ai, :harness]`:
  - cancel-ok baseline test
  - cancel-not-available baseline test
  - cancel-failed baseline test

### Deliverables

- Hardened baseline cancel matrix assertions for terminal lifecycle
  exclusivity invariants across built-in backends.

### Exit criteria

- Runtime matrix tests verify deterministic terminal exclusivity semantics for
  baseline cancel outcomes, preventing terminal-state regressions across
  `jido_ai` and `harness`.

### Completion notes

- Added shared terminal-exclusivity helper and applied it to baseline cancel
  matrix tests in:
  - `test/jido_conversation/runtime/llm_cancel_telemetry_matrix_test.exs`

## Phase 59: Cancel cause-variant terminal-exclusivity matrix parity hardening

### Objectives

- Harden runtime cancellation parity coverage by enforcing terminal lifecycle
  exclusivity semantics across cancel cause variants.
- Ensure cause-link and invalid-cause cancel scenarios emit exactly one
  terminal `canceled` lifecycle and never regress to terminal `completed` or
  `failed` events for the same effect.

### Tasks

- Apply shared terminal-exclusivity assertion helper to cancel cause-variant
  matrix scenarios across `[:jido_ai, :harness]`:
  - cancel-ok explicit `cause_id`
  - cancel-ok invalid `cause_id` fallback
  - cancel-not-available explicit `cause_id`
  - cancel-not-available invalid `cause_id` fallback
  - cancel-failed explicit `cause_id`
  - cancel-failed invalid `cause_id` fallback

### Deliverables

- Hardened cause-variant cancel matrix assertions for terminal lifecycle
  exclusivity invariants across built-in backends.

### Exit criteria

- Runtime matrix tests verify deterministic terminal exclusivity semantics for
  cause-link and invalid-cause cancel outcomes, preventing terminal-state
  regressions across `jido_ai` and `harness`.

### Completion notes

- Applied shared terminal-exclusivity helper to cause-variant cancel matrix
  tests in:
  - `test/jido_conversation/runtime/llm_cancel_telemetry_matrix_test.exs`

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

## Open decisions (resolved)

- Stream defaults:
  - resolved as stream-first (`stream?: true`) for built-in backends by default
    through config (`llm.default_stream?` and backend-specific overrides)
- Reasoning/thinking representation:
  - resolved as normalized lifecycle `:thinking` with chunk payload in
    `LLM.Event.content`
- Model/provider attribution minimums:
  - resolved as backend/provider/model fields included whenever known, with
    started/terminal lifecycle events expected to carry known attribution
- Retryability classification map:
  - resolved for built-in adapters with explicit HTTP status mapping:
    `401/403` non-retryable auth, `408` retryable timeout, `409/425/429/5xx`
    retryable provider, other `4xx` non-retryable provider
