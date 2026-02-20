# Runtime Execution Flow

This sequence describes what happens from ingress to projections.

## End-to-end sequence

```mermaid
sequenceDiagram
  participant Host as Host App
  participant Pipeline as Ingest.Pipeline
  participant Journal as Signal Journal
  participant Bus as Signal Bus
  participant Sub as Runtime IngressSubscriber
  participant Coord as Runtime Coordinator
  participant Part as PartitionWorker
  participant Sched as Scheduler
  participant Red as Reducer
  participant EffMgr as EffectManager
  participant EffW as EffectWorker
  participant Proj as Projections

  Host->>Pipeline: ingest(attrs, opts)
  Pipeline->>Pipeline: contract normalize/validate + dedupe
  Pipeline->>Journal: record(signal, cause_id)
  Pipeline->>Bus: publish(signal)
  Bus->>Sub: persistent delivery
  Sub->>Coord: enqueue(signal)
  Coord->>Part: enqueue by hash(subject)
  Part->>Sched: schedule(queue, scheduler_state, applied_ids)
  Sched-->>Part: selected ready entry
  Part->>Red: apply_event(state, signal, context)
  Red-->>Part: new_state + directives

  alt start/cancel effect directive
    Part->>EffMgr: start_effect/cancel_conversation
    EffMgr->>EffW: spawn/cancel worker
    EffW->>Pipeline: ingest conv.effect.* lifecycle events
  end

  alt emit output directive
    Part->>Pipeline: ingest conv.out.* event
  end

  Part->>Pipeline: ingest conv.applied.* marker
  Proj->>Pipeline: conversation_events/replay
  Proj-->>Host: timeline / llm_context
```

## Ordering model

- Record order:
  - preserved by journal append sequence
- Processing order:
  - chosen by scheduler based on causal readiness, priority, and fairness

This split is intentional and tested for determinism/replay parity.

## Partition model

- `subject` hashes to a partition id.
- Each partition has:
  - its own queue
  - scheduler state
  - conversation state map
  - applied signal-id set

This gives per-conversation locality while supporting horizontal scaling.

## Directive model

Reducer directives currently include:

- `:emit_applied_marker`
- `:start_effect`
- `:cancel_effects`
- `:emit_output`

Directive execution happens in `PartitionWorker`, not in `Reducer`.
