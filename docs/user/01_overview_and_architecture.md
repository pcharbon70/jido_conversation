# 01. Overview and Architecture

`jido_conversation` is an embeddable, event-driven runtime for conversation
workflows. Your host application publishes conversation events, and the runtime
handles deterministic state transitions, effect execution, and projection
queries.

## What this library gives you

- Journal-first event ingestion with contract validation
- Deterministic scheduler and pure reducer flow
- Runtime effect handling for `:llm`, `:tool`, and `:timer`
- Projection APIs for UI timeline and LLM context
- Runtime health and telemetry snapshots

## Ownership boundary

`jido_conversation` is the runtime substrate for conversation events. It keeps
state transitions deterministic and exposes projections, but it does not define
mode-specific business pipelines. In the Jido stack, mode orchestration and
policy-gated execution are handled by `jido_code_server`, which publishes
canonical conversation events consumed here.

## Core public APIs

- `JidoConversation.ingest/2`
- `JidoConversation.timeline/2`
- `JidoConversation.llm_context/2`
- `JidoConversation.health/0`
- `JidoConversation.telemetry_snapshot/0`

## Signal families

- `conv.in.*`: inbound user/control/timer signals
- `conv.applied.*`: reducer application markers
- `conv.effect.*`: effect lifecycle events
- `conv.out.*`: outbound UI-facing conversation output
- `conv.audit.*`: audit and trace events

## Runtime component map

1. Contract normalization (`JidoConversation.Signal.Contract`)
2. Journal + bus ingestion (`JidoConversation.Ingest.Pipeline`)
3. Partition scheduling + reducer apply (`JidoConversation.Runtime.Coordinator` + `JidoConversation.Runtime.Reducer`)
4. Effect execution (`JidoConversation.Runtime.EffectManager` + `JidoConversation.Runtime.EffectWorker`)
5. Projection reads (`JidoConversation.Projections`)

```mermaid
flowchart LR
  A["Host app"] --> B["JidoConversation.ingest/2"]
  B --> C["Contract gate"]
  C --> D["Journal append + bus publish"]
  D --> E["Runtime coordinator"]
  E --> F["Pure reducer"]
  F --> G["Directives"]
  G --> H["Effect runtime"]
  H --> I["conv.effect.* / conv.out.* events"]
  I --> E
  D --> J["Replay + projections"]
```

## Conversation identity

Use one stable `conversation_id` per conversation thread. It is carried in the
signal `subject`, and it is the partition key for scheduling, replay, and
projection queries.
