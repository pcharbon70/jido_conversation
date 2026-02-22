# 01. System Architecture

This guide describes the runtime shape of `jido_conversation` and how core
modules collaborate.

## Application boot graph

`JidoConversation.Application` starts four top-level subsystems:

- `JidoConversation.Telemetry`
- `JidoConversation.Signal.Supervisor`
- `JidoConversation.Ingest.Pipeline`
- `JidoConversation.Runtime.Supervisor`

```mermaid
flowchart TD
  A["JidoConversation.Application"] --> B["Telemetry"]
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

## End-to-end event path

```mermaid
flowchart LR
  A["Host ingest"] --> B["Signal.Contract"]
  B --> C["Ingest.Pipeline"]
  C --> D["Journal append"]
  C --> E["Bus publish"]
  E --> F["IngressSubscriber"]
  F --> G["Coordinator"]
  G --> H["PartitionWorker"]
  H --> I["Reducer"]
  I --> J["Directives"]
  J --> K["EffectManager / Outbound adapter"]
  K --> C
  D --> L["Projections + Replay"]
```

## Architectural intent

- Keep reducer logic pure and deterministic.
- Route all side effects through runtime directives.
- Preserve journal-first ingestion as the durable source of truth.
- Expose only stable public APIs through `JidoConversation`.

## Public API surface

- `JidoConversation.ingest/2`
- `JidoConversation.timeline/2`
- `JidoConversation.llm_context/2`
- `JidoConversation.health/0`
- `JidoConversation.telemetry_snapshot/0`
