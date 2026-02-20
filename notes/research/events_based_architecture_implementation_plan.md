# Event-Based Conversation Architecture Implementation Plan

This plan translates the research in `notes/research/events_based_conversation.md` into an implementation roadmap for this repository.

## Planning assumptions

- Conversation identity is carried via `Jido.Signal.subject`.
- State transitions are deterministic and side effects are emitted as directives.
- Journal insertion order is immutable record order; runtime processing may be priority-ordered.
- Architecture is partitioned-worker first, not one persistent subscriber per conversation.

## Phase 0: Architecture baseline (3-5 days)

### Objectives

- Finalize decisions that affect all downstream code.
- Define target behavior and operational constraints before implementation.

### Tasks

- Finalize aggregate model and canonical identity (`conversation_id == subject`).
- Finalize event stream taxonomy:
  - `conv.in.*`
  - `conv.applied.*`
  - `conv.effect.*`
  - `conv.out.*`
  - `conv.audit.*`
- Finalize priority classes:
  - `P0` control-plane interrupts
  - `P1` state-critical
  - `P2` state-informative
  - `P3` high-volume low-criticality
- Define SLOs:
  - abort latency
  - end-to-end response latency
  - replay correctness target
  - delivery/retry error budget
- Define failure-mode matrix and rollback strategy.

### Deliverables

- ADR set for identity, ordering, ack policy, and partitioning.
- Event naming and taxonomy conventions.
- SLO and failure-mode docs.

### Exit criteria

- Team agreement on record-order vs processing-order semantics and ack policy.

## Phase 1: Project foundation and runtime skeleton (3-4 days)

### Objectives

- Stand up a runnable baseline with supervision and quality gates.

### Tasks

- Wire top-level supervision tree for:
  - `Jido.Signal.Bus`
  - `Jido.Signal.Journal`
  - router/dispatch supervisors
  - runtime supervisors
- Add baseline static quality dependencies/tasks (`credo`, `dialyxir`) so pre-commit and CI can pass.
- Add environment config for:
  - journal adapter (dev/test/prod)
  - partition count
  - retry defaults
  - backpressure limits
- Add basic health checks/startup assertions.

### Deliverables

- Booting app with empty event pipeline.
- Environment and runtime config templates.
- Green baseline CI pipeline.

### Exit criteria

- App boots in dev/test and CI passes with no runtime wiring errors.

## Phase 2: Event contract and validation boundary (4-6 days)

### Objectives

- Enforce a canonical envelope at the system boundary.

### Tasks

- Implement normalization/validation boundary around `Jido.Signal`.
- Enforce required fields:
  - `type`
  - `source`
  - `id`
  - `subject`
- Add optional causality support (`cause_id`) and correlation metadata.
- Define type families and payload contracts for each stream namespace.
- Implement contract versioning and compatibility policy.
- Add negative tests for malformed/unsupported signals.

### Deliverables

- Signal schema modules/types.
- Validation and normalization layer.
- Contract and rejection-path tests.

### Exit criteria

- No event enters runtime without passing validation.

## Phase 3: Journal-first ingress pipeline (5-7 days)

### Objectives

- Guarantee durable traceability for all incoming events.

### Tasks

- Implement ingress adapters for:
  - messaging/user input
  - tool lifecycle callbacks
  - LLM lifecycle callbacks
  - control-plane inputs (abort/retry/stop)
  - timer/scheduler signals
- Implement deterministic ingest flow:
  - normalize -> append to journal -> publish to bus
- Implement idempotency/deduplication strategy keyed by event identity and conversation.
- Add causality linkage where events are derived from prior events.

### Deliverables

- Ingress adapter modules.
- Journal append wrappers.
- Ingestion integration tests and replayability checks.

### Exit criteria

- Every consumed event is journaled and replayable in chronological order.

## Phase 4: Conversation runtime reducer and scheduler (7-10 days)

### Objectives

- Build the core event-application engine with deterministic behavior.

### Tasks

- Implement partitioned workers (hash by `subject`).
- Build deterministic scheduler function:
  - priority-aware
  - causality-aware
  - fairness-aware
- Implement pure reducer (`apply_event/2`) returning:
  - next state
  - emitted directives
- Define runtime state shape:
  - in-flight tool map
  - in-flight LLM step map
  - policy flags
  - projection pointers
- Emit `conv.applied.*` markers after successful application.

### Deliverables

- Scheduler and reducer modules.
- Partition runtime supervisor and worker implementation.
- Deterministic replay test suite.

### Exit criteria

- Replaying the same event log always yields the same state and projections.
- `P0` events preempt lower-priority work predictably.

## Phase 5: Effect runtime, cancellation, retry, timeout (6-8 days)

### Objectives

- Execute side effects reliably without blocking reducer progress.

### Tasks

- Implement directive executor workers for LLM/tool/timer effects.
- Implement effect lifecycle events:
  - started
  - progress
  - completed
  - failed
  - canceled
- Implement cancellation path for `abort` and `stop generation`.
- Implement retry/backoff/timeout policies per effect class.
- Ensure cancellation cleans up child processes and in-flight state references.

### Deliverables

- Effect runtime modules and supervisors.
- Cancellation and retry policy implementation.
- Concurrency and timeout conformance tests.

### Exit criteria

- Reducer never blocks on long-running work.
- Abort latency meets SLO under normal load.

## Phase 6: Messaging integration and projections (5-7 days)

### Objectives

- Integrate channel adapters while keeping runtime channel-agnostic.

### Tasks

- Integrate `Jido.Messaging` ingress for user/channel messages.
- Add outbound projection flow for assistant/tool updates.
- Build projection functions for:
  - user-facing timeline
  - LLM context (thread projection)
- Implement token-delta coalescing policy for throughput and UI quality.
- Validate ordering guarantees for per-conversation output streams.

### Deliverables

- Messaging adapter integration.
- Projection modules for runtime state -> user/LLM views.
- End-to-end prompt-to-response test cases.

### Exit criteria

- Same core behavior across channels with consistent per-conversation output ordering.

## Phase 7: Observability, replay, and audit tooling (5-7 days)

### Objectives

- Make diagnosis and accountability first-class capabilities.

### Tasks

- Add telemetry for:
  - queue depth
  - apply latency
  - abort latency
  - retry counts
  - DLQ rates
  - dispatch failures
- Expose stream subscriptions via bus and PubSub/webhook dispatch.
- Add operator tooling:
  - replay conversation
  - trace cause/effect chain
  - inspect checkpoints
- Add audit-oriented event projection (`conv.audit.*`) as needed.

### Deliverables

- Dashboards and alerts.
- Replay and trace tooling.
- Audit query path docs.

### Exit criteria

- Operators can answer "why did this behavior happen?" from stored event history.

## Phase 8: Reliability and scale hardening (7-10 days)

### Objectives

- Validate behavior under load and fault conditions.

### Tasks

- Validate ack semantics and checkpoint recovery behavior.
- Exercise DLQ and re-drive paths.
- Load test high-volume streams (especially token deltas).
- Tune:
  - `max_in_flight`
  - `max_pending`
  - partition counts
  - retry caps/timeouts
- Run fault injection:
  - transient provider errors
  - slow/failed dispatch
  - subscriber restarts
  - partial outages

### Deliverables

- Capacity and tuning report.
- Resilience test suite in CI/staging.
- Production default configuration recommendations.

### Exit criteria

- SLOs hold at target load.
- System degrades gracefully under overload and recovers predictably.

## Phase 9: Production launch readiness (3-5 days)

### Objectives

- Prepare a greenfield event-based runtime for production launch.

### Tasks

- Add a launch-readiness operator report that aggregates:
  - health state
  - runtime telemetry
  - subscription/checkpoint pressure
  - DLQ load
- Define launch thresholds and go/no-go checks.
- Prepare incident runbooks for degraded health, queue pressure, and DLQ growth.
- Run launch-readiness drills in staging and capture baseline snapshots.

### Deliverables

- Launch-readiness checklist and report format.
- Operator runbook for launch and initial incident response.
- Production threshold defaults for queue depth, dispatch failures, and DLQ tolerance.

### Exit criteria

- Operators can determine launch status from one report (`ready`, `warning`, `not_ready`).
- Staging launch drills pass with no critical readiness issues.

## Cross-phase quality gates

- Determinism: replayed state equals live state for sampled conversations.
- Contract integrity: invalid events rejected at boundary.
- Responsiveness: abort and reply latency SLOs met.
- Reliability: retry/DLQ/checkpoint paths continuously tested.
- Operability: dashboards and alerts available before production launch.

## Suggested timeline (high level)

- Weeks 1-2: Phases 0-2
- Weeks 3-5: Phases 3-5
- Weeks 6-7: Phases 6-7
- Weeks 8-9: Phases 8-9

## Recommended immediate next backlog items

1. Automate periodic launch-readiness snapshots and alerting on `not_ready` reports.
2. Add historical readiness trend storage for operational review.
3. Expand replay determinism checks with sampled production traffic in staging.
4. Add runbook drills to CI/staging smoke suites.
