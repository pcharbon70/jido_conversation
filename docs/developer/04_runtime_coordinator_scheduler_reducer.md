# 04. Runtime Coordinator, Scheduler, and Reducer

This guide explains deterministic runtime processing after ingestion.

## Core modules

- `Runtime.IngressSubscriber`
- `Runtime.Coordinator`
- `Runtime.PartitionWorker`
- `Runtime.Scheduler`
- `Runtime.Reducer`

## Processing sequence

```mermaid
sequenceDiagram
  participant Sub as IngressSubscriber
  participant Coord as Coordinator
  participant Part as PartitionWorker
  participant Sched as Scheduler
  participant Red as Reducer

  Sub->>Coord: enqueue(signal)
  Coord->>Part: route by hash(subject)
  Part->>Sched: schedule(queue, state, applied_ids)
  Sched-->>Part: selected ready entry
  Part->>Red: apply_event(conversation_state, signal, context)
  Red-->>Part: next_state + directives
```

## Tool-call loop in host orchestration (`jido_code_server`)

When `jido_conversation` is hosted by `jido_code_server` conversation
orchestration, tool calls follow this deterministic loop:

```mermaid
sequenceDiagram
  participant Client as Client
  participant Project as Project.Server
  participant Conv as Conversation.Agent
  participant Red as Domain.Reducer
  participant LLMInst as RunLLMInstruction
  participant LLM as Conversation.LLM
  participant ToolInst as RunToolInstruction
  participant Bridge as ToolBridge
  participant Runner as Project.ToolRunner
  participant Journal as JournalBridge

  Client->>Project: conversation_call(conversation.user.message)
  Project->>Conv: call/cast canonical signal
  Conv->>Red: enqueue + drain
  Red-->>Conv: intent(kind=run_llm)
  Conv->>LLMInst: execute instruction
  LLMInst->>LLM: start_completion(tool_specs, llm_context)
  LLM-->>Conv: conversation.llm.* + conversation.tool.requested
  Conv->>Red: ingest returned signals
  Red-->>Conv: intent(kind=run_tool)
  Conv->>ToolInst: execute instruction
  ToolInst->>Bridge: handle_tool_requested(...)
  Bridge->>Runner: run / run_async
  Runner-->>Bridge: conversation.tool.completed | failed
  Bridge-->>Conv: canonical tool result signals
  Conv->>Red: ingest tool result
  Red-->>Conv: intent(kind=run_llm) when pending tools empty
  Conv->>LLMInst: follow-up LLM turn
  Conv->>Journal: bridge conversation.* into conv.*
```

Notes:

- Tool calls are emitted by the LLM turn as `conversation.tool.requested`.
- Reducer keeps pending tool state and only triggers the follow-up LLM turn when
  the pending tool set becomes empty.
- `JournalBridge` persists canonical `conv.*` streams (`conv.in.*`,
  `conv.out.*`, and audit/effect events) for replay and projections.

## Partition model

- Conversation `subject` determines partition assignment.
- Each partition keeps isolated queue/scheduler/conversation state.
- This preserves conversation locality while allowing concurrent partitions.

## Reducer contract

`Reducer.apply_event/3` returns:

- updated conversation state
- directives for side effects (`:emit_applied_marker`, `:start_effect`,
  `:cancel_effects`, `:emit_output`)

Reducer never performs direct side effects.

## Scheduler behavior

`Runtime.Scheduler` resolves ready events with deterministic ordering rules
(causality + fairness + priority). The order can differ from append order while
remaining reproducible under replay.

## Applied markers

For non-`conv.applied.*` events, runtime emits an applied marker directive to
record reducer application lineage and scheduling context.
