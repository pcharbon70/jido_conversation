# 07. Observability and Health

The library exposes a lightweight health API and a structured telemetry
snapshot for runtime diagnostics.

## Health snapshot

```elixir
health = Jido.Conversation.health()
```

Returned fields:

- `status` (`:ok` or `:degraded`)
- `bus_name`
- `bus_alive?`
- `runtime_supervisor_alive?`
- `runtime_coordinator_alive?`

Use this for readiness/liveness checks in the host application.

## Telemetry snapshot

```elixir
snapshot = Jido.Conversation.telemetry_snapshot()
```

Top-level sections include:

- queue depth and partition counts
- apply/abort latencies
- dispatch retry and DLQ counters
- LLM lifecycle and streaming metrics

## LLM telemetry focus points

- `snapshot.llm.lifecycle_counts`
- `snapshot.llm.lifecycle_by_backend`
- `snapshot.llm.retry_by_category`
- `snapshot.llm.stream_duration_ms`
- `snapshot.llm.stream_chunks`
- `snapshot.llm.cancel_results`
- `snapshot.llm.cancel_latency_ms`

## Practical alerting ideas

1. Alert on sustained growth in `retry_by_category["timeout"]` or
   `retry_by_category["transport"]`.
2. Alert when `lifecycle_counts.failed` rises with no corresponding increase in
   `completed`.
3. Track stream chunk totals and stream durations by backend for regression
   detection.
