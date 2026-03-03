# How It Works

`jido_conversation` is an embeddable event-driven conversation runtime.

At a high level:

- Host app ingests events into the runtime
- Events pass the contract boundary
- Events are written to the journal and published to the bus
- Runtime scheduler and reducer apply events deterministically per conversation
- Effects emit follow-up lifecycle events
- Projections build timeline and LLM context views

```mermaid
flowchart LR
  A["Host app calls ingest"] --> B["Contract normalize and validate"]
  B --> C["Journal append"]
  C --> D["Bus publish"]
  D --> E["Partition scheduler"]
  E --> F["Pure reducer apply"]
  F --> G["Directives"]
  G --> H["Effect runtime"]
  H --> I["More events"]
  I --> E
  C --> J["Projection reads"]
```

## Core concepts

### Conversation identity

- `conversation_id` is carried by signal `subject`.
- All per-conversation partitioning, replay, and projections use this value.

### Stream namespaces

- `conv.in.*` incoming/control/timer events
- `conv.applied.*` reducer-application markers
- `conv.effect.*` effect lifecycle events
- `conv.out.*` user-facing output events
- `conv.audit.*` audit/trace events

### Contract boundary

Every signal must satisfy:

- required envelope fields (`type`, `source`, `id`, `subject`)
- supported namespace prefix
- supported contract version (`extensions.contract_major`, currently `1`)
- required payload keys per stream family

### Determinism model

- Journal order is durable record order.
- Runtime processing can prioritize events (for responsiveness), but scheduler
  rules are deterministic.
- Reducer logic is pure: state transitions are separate from side effects.
- Replay and parity tests verify reproducibility of outcomes.

## Public entry points

- `Jido.Conversation.Ingest.ingest/2`
- `Jido.Conversation.Projections.timeline/2`
- `Jido.Conversation.Projections.llm_context/2`
- `Jido.Conversation.Health.status/0`
- `Jido.Conversation.Runtime.start_conversation/1`
- `Jido.Conversation.Runtime.ensure_conversation/1`
- `Jido.Conversation.Runtime.send_user_message/3`
- `Jido.Conversation.Runtime.record_assistant_message/3`
- `Jido.Conversation.Runtime.configure_llm/3`
- `Jido.Conversation.Runtime.configure_skills/2`
- `Jido.Conversation.Runtime.generate_assistant_reply/2`
- `Jido.Conversation.Runtime.await_generation/3`
- `Jido.Conversation.Runtime.send_and_generate/3`
- `Jido.Conversation.Runtime.cancel_generation/2`
- `Jido.Conversation.Runtime.derived_state/1`
- `Jido.Conversation.Runtime.timeline/1`
- `Jido.Conversation.Runtime.thread/1`
- `Jido.Conversation.Runtime.thread_entries/1`
- `Jido.Conversation.Runtime.messages/2`
- `Jido.Conversation.Runtime.llm_context/2`
- `Jido.Conversation.Telemetry.snapshot/0`
