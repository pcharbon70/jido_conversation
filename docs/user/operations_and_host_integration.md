# Operations and Host Integration

`jido_conversation` is a runtime library. Operational policy is owned by the
host application.

`jido_conversation` does not implement conversation mode/strategy orchestration.
That business logic belongs to host orchestration (for example, `jido_code_server`).

## Health

Use `JidoConversation.health/0` in host health/readiness endpoints:

```elixir
%{
  status: :ok | :degraded,
  bus_name: _,
  bus_alive?: _,
  runtime_supervisor_alive?: _,
  runtime_coordinator_alive?: _
} = JidoConversation.health()
```

## Telemetry snapshot

Use `JidoConversation.telemetry_snapshot/0` for metrics polling and dashboards.

It includes:

- queue depth (`total`, `by_partition`)
- apply latency summary (`count`, `avg_ms`, `min_ms`, `max_ms`)
- abort latency summary (`count`, `avg_ms`, `min_ms`, `max_ms`)
- llm lifecycle counters (`started`, `progress`, `completed`, `failed`, `canceled`)
- llm lifecycle counters grouped by backend
- llm stream duration summary and stream chunk totals (`delta`, `thinking`, `total`)
- llm cancellation latency summary
- llm retry categories and cancellation result counters
- retry, DLQ, and dispatch failure counters
- last dispatch failure metadata

## Host-owned responsibilities

Host applications should own:

- release gating and deployment policy
- alerting/on-call escalation
- incident runbooks and rollback decisions
- environment-specific tuning of runtime knobs
- conversation mode, strategy, and tool execution orchestration

## Runtime knobs to tune in host config

- `runtime_partitions`
- `persistent_subscription.max_in_flight`
- `persistent_subscription.max_pending`
- effect runtime timeout/retry values per class (`llm`, `tool`, `timer`)

## Recommended follow-up docs

- `docs/host_integration_patterns.md`
- `docs/host_testing_handoff_checklist.md`
- `docs/operations/slo_and_error_budget.md`
- `docs/operations/failure_mode_matrix.md`
