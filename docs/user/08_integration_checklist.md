# 08. Integration Checklist

Use this checklist when embedding `jido_conversation` in a host system.

## Configuration

- Set `Jido.Conversation.EventSystem` explicitly per environment.
- Configure `llm.default_backend` and backend `module` values.
- Tune `effect_runtime` max attempts, backoff, and timeout by class.

## Ingestion discipline

- Use stable conversation IDs in signal `subject`.
- Prefer ingest adapters for messaging/control/timer/outbound paths.
- Always include `extensions.contract_major: 1` in custom direct ingest payloads.
- Use `cause_id` for derived events to preserve traceability.

## Runtime behavior

- Treat reducers as pure; route side effects through emitted directives only.
- Use control events (`abort_requested`) for cancellation, not direct process
  manipulation.
- For test paths, use `simulate_effect` payloads instead of bypassing runtime.

## Projection usage

- Use timeline projection for UI rendering.
- Use LLM context projection for prompt assembly.
- Use replay APIs to debug lifecycle/event ordering issues.

## Observability

- Poll `Jido.Conversation.health/0` in host readiness checks.
- Capture `Jido.Conversation.telemetry_snapshot/0` on intervals for trend
  dashboards.
- Watch `llm.retry_by_category` and lifecycle counters for backend instability.

## Failure handling

- Expect non-retryable categories (`auth`, `config`, `canceled`) to fail fast.
- Expect retryable categories (`provider`, `timeout`, `transport`) to emit
  retrying progress lifecycle events.
- Implement bounded retries around host ingest calls under bus backpressure.
