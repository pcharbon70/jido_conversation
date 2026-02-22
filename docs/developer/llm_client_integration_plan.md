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
