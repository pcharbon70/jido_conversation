# Component Map

This map summarizes major runtime components and the boundaries between them.

## Top-level dependency graph

```mermaid
flowchart TD
  A["Jido.Conversation.Application"] --> B["Telemetry"]
  A --> C["Signal.Supervisor"]
  A --> D["Ingest.Pipeline"]
  A --> E["Runtime.Supervisor"]

  C --> F["Jido.Signal.Bus"]
  D --> F

  E --> G["IngressSubscriber"]
  E --> H["Coordinator"]
  E --> I["PartitionWorker (N)"]
  E --> J["EffectManager"]
  J --> K["EffectWorker (dynamic)"]
```

## Component table

| Component | Primary modules | Responsibility | Key outputs |
| --- | --- | --- | --- |
| Public API facade | `Jido.Conversation` | Stable app-facing entry points | Ingest/projection/health/telemetry APIs |
| Contract boundary | `Jido.Conversation.Signal.Contract` | Normalize + validate envelope, namespace, version, payload requirements | Canonical validated signals or rejection errors |
| Signal infra | `Jido.Conversation.Signal.Supervisor`, `Jido.Signal.Bus` | Bus startup/routing/replay plumbing | Published signals, replay access |
| Ingestion | `Jido.Conversation.Ingest.Pipeline` | Journal-first ingest with dedupe and optional `cause_id` linkage | Journaled + published events |
| Runtime ingress | `Jido.Conversation.Runtime.IngressSubscriber` | Persistent bus subscription, contract re-check, routing to runtime | Enqueued runtime events |
| Partition routing | `Jido.Conversation.Runtime.Coordinator` | Hash-by-subject partition assignment | Partition worker enqueue calls |
| Deterministic scheduler | `Jido.Conversation.Runtime.Scheduler` | Priority + causality + fairness event selection | Next ready queue entry |
| Pure reducer | `Jido.Conversation.Runtime.Reducer` | Conversation state transitions and directive emission | Updated state + directives |
| Directive executor | `Jido.Conversation.Runtime.PartitionWorker` | Applies reducer output, executes directives, emits telemetry | Applied markers, effect starts/cancels, outputs |
| Effect orchestration | `Jido.Conversation.Runtime.EffectManager`, `Jido.Conversation.Runtime.EffectWorker` | In-flight worker lifecycle, retries, timeout, cancellation | `conv.effect.*` lifecycle events |
| Projection layer | `Jido.Conversation.Projections.*` | Materialized timeline and LLM context views from events | User/UI and model context views |
| Runtime metrics | `Jido.Conversation.Telemetry` | Aggregates telemetry events for host polling | `telemetry_snapshot/0` metrics |

## Boundary rules

- `Reducer` must stay pure.
- `PartitionWorker` is the only place reducer directives are executed.
- `Ingest.Pipeline` is the only write boundary to journal + bus for normal event entry.
- Host app should depend on `Jido.Conversation` public APIs, not deep internals.
