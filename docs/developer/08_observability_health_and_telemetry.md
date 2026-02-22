# 08. Observability, Health, and Telemetry

This guide covers operational introspection internals.

## Health endpoint internals

`JidoConversation.health/0` delegates to `Health.status/0`, which validates:

- bus process alive
- runtime supervisor alive
- runtime coordinator alive

It returns `:ok` only when all required runtime processes are healthy.

## Telemetry aggregation model

`JidoConversation.Telemetry` is a GenServer that attaches handlers and
aggregates counters/latencies into one snapshot.

Tracked domains:

- runtime queue depth and apply/abort latency
- dispatch retry/DLQ/dispatch errors
- LLM lifecycle counts and backend dimensions
- LLM stream duration/chunk counters
- LLM retry-by-category and cancel results

## Important event families

- `[:jido_conversation, :runtime, :llm, :lifecycle]`
- `[:jido_conversation, :runtime, :llm, :retry]`
- `[:jido_conversation, :runtime, :llm, :cancel]`

## Retry-category semantics

Retry counters use deterministic precedence:

1. `retry_category` metadata
2. fallback to `error_category`

Blank category values are ignored.

## Host-facing API

- `JidoConversation.telemetry_snapshot/0`
- `JidoConversation.health/0`

These endpoints are polling-safe and intended for dashboards/readiness checks.
