# Host Integration Patterns (Observability and Deployment)

This document defines how host applications should integrate `jido_conversation`
for operations concerns while keeping this library focused on runtime behavior.

## Responsibility boundary

`jido_conversation` owns:

- Event contract validation at ingress
- Journal-first ingestion and replay primitives
- Deterministic scheduling/reducer behavior
- Runtime telemetry emission and snapshot aggregation

Host applications own:

- Deployment policy and release gating
- Alerting, paging, and runbook workflows
- Environment-specific scaling/tuning policy
- Incident response and rollback decisions

## Host observability integration

### 1. Runtime health check endpoint

Expose `JidoConversation.health/0` through the host application's health route.
Treat `status: :degraded` as a failed dependency signal for readiness.

```elixir
defmodule MyApp.ConversationHealth do
  def snapshot do
    JidoConversation.health()
  end
end
```

### 2. Metrics scrape/forwarder

Poll `JidoConversation.telemetry_snapshot/0` on a short interval and forward to
your metrics backend.

Recommended fields:

- `queue_depth.total`
- `queue_depth.by_partition`
- `apply_latency_ms`
- `abort_latency_ms`
- `llm.lifecycle_counts`
- `llm.lifecycle_by_backend`
- `llm.stream_duration_ms`
- `llm.stream_chunks`
- `llm.cancel_latency_ms`
- `llm.retry_by_category`
- `llm.cancel_results`
- `retry_count`
- `dlq_count`
- `dispatch_failure_count`

### 3. Telemetry event subscription

If the host already centralizes telemetry processing, subscribe to the same
event families emitted by this library:

- `[:jido_conversation, :runtime, :queue, :depth]`
- `[:jido_conversation, :runtime, :apply, :stop]`
- `[:jido_conversation, :runtime, :abort, :latency]`
- `[:jido_conversation, :runtime, :llm, :lifecycle]`
- `[:jido_conversation, :runtime, :llm, :cancel]`
- `[:jido_conversation, :runtime, :llm, :retry]`
- `[:jido, :signal, :subscription, :dispatch, :retry]`
- `[:jido, :signal, :subscription, :dlq]`
- `[:jido, :signal, :bus, :dispatch_error]`

## Host deployment policy integration

### 1. Pre-deploy checks

Before promotion, host CI/CD should validate:

- test/lint/static checks for the host app and this dependency
- replay parity checks on sampled conversations in staging
- queue/latency error budget not currently exhausted

### 2. Release gate example

Use host-level gates against SLO targets defined in
`docs/operations/slo_and_error_budget.md`.

```elixir
defmodule MyApp.ReleaseGate do
  def ready_for_promote? do
    metrics = JidoConversation.telemetry_snapshot()

    metrics.dispatch_failure_count == 0 and
      metrics.dlq_count == 0 and
      metrics.queue_depth.total < 1_000
  end
end
```

### 3. Rollback and re-drive are host workflows

When deployment or runtime regressions occur, host runbooks should drive:

- rollback decisioning
- replay/re-drive invocation
- incident communication and escalation

The library provides runtime signals and replay primitives, but does not choose
or automate policy.

## Host configuration patterns

Set environment-specific runtime knobs in the host configuration for
`JidoConversation.EventSystem`, especially:

- `runtime_partitions`
- `persistent_subscription.max_in_flight`
- `persistent_subscription.max_pending`
- effect runtime timeouts/retries by class

Tune these values in host environments using load-test and incident feedback.
