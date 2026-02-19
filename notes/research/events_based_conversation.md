# Event-Based Conversation Architecture for an Elixir LLM Coding Assistant

## Context and design goals

A turn-based conversation loop (“user prompt → LLM response”) becomes a bottleneck once you introduce real-world agent behavior: streaming generation, multi-step tool use, retries, timeouts, user cancellation, multi-channel messaging, and observability. Your contention—that conversation should be modeled as an event-driven system where state is a pure function of applied events—is closely aligned with event sourcing and with the “separate deterministic state transitions from side effects” approach promoted in Jido’s core loop.

The key requirements implied by your description are:

- Multiple event sources (human prompts, messaging channels, tool lifecycle, LLM lifecycle, scheduler/timeouts, abort/cancel, internal policy decisions).
- A single ordered queue for processing, with explicit prioritization (so urgent control-plane events like “abort” can preempt low-value/high-volume data-plane events like token deltas).
- Conversation state derived from applied events, not from mutable “current transcript” blobs (replayable and explainable).
- Pub-sub observability with multiple subscribeable “streams” of events (raw ingress, normalized, applied/reduced, side-effects, telemetry).
- Distributed-friendly primitives: standardized event envelope, routing, persistence, replay, checkpointing, and failure handling.

The Jido ecosystem you listed already contains many of the building blocks needed to make this architecture coherent and operationally robust: an explicit signal envelope built on CloudEvents, a bus with persistent subscriptions and DLQ, and a journal with causality + conversation grouping.

## Jido ecosystem capabilities that map directly to an event-based conversation

### Deterministic state transitions and effect isolation in Jido core

Jido’s core loop is explicitly “Signal → Action → cmd/2 → {agent, directives} → runtime executes directives,” with a clear separation: state changes are deterministic and side effects are represented as directives interpreted by a runtime (AgentServer).

This contract is unusually well-suited for an event-sourced conversation engine:

- Events (“Signals”) arrive and are routed to handlers (“Actions”).
- Actions produce a new state plus a list of effect descriptions (“Directives”), keeping the state application step testable and replayable.
- Directives include effect primitives that matter for conversation engines, such as emitting signals, spawning processes/agents, stopping children, scheduling delayed work, and stopping the agent process itself.

### A canonical append-only conversation record is already a first-class concept

Jido v2 introduces `Thread` as an append-only log of “what happened” in a conversation/workflow, with LLM context derived via projection functions rather than stored directly. This is conceptually the same stance you’re taking (“state is a function of applied events”).

### Jido.Signal as a standardized event envelope and routing substrate

`Jido.Signal` is CloudEvents-compatible (v1.0.2) and documents required attributes like `specversion`, `id`, `source`, and `type`, with “signals are universal message format” semantics.

Jido also extends beyond pure CloudEvents with Jido-specific fields (e.g., instructions/options/dispatch/metadata), enabling richer agent/system semantics without abandoning portability.

For routing, `Jido.Signal.Router` provides trie-based dot-notation routing with wildcard patterns, match functions, and explicit handler priorities—useful for building clean “event → handler” maps and consistent signal taxonomies.

### Jido.Signal.Bus for pub/sub + persistent subscriptions + DLQ + partitions

`Jido.Signal.Bus` is explicitly designed as a central hub for publishing and subscribing to signals, with routing based on path patterns, internal log + replay, and snapshot mechanisms.

The event bus guide describes persistent subscriptions with acknowledgments, checkpointing, retry configuration, and dead-letter queue support, including backpressure-like controls (`max_in_flight`, `max_pending`).

It also describes horizontal scaling by partitions (partition workers) and notes that persistent subscriptions are handled by the main bus process “to honor backpressure,” which is a critical scaling consideration for “one subscriber per conversation” designs.

### Jido.Signal.Journal for event sourcing, causality, and conversation grouping

The `Signal Journal` guide frames the journal as durable append-only signal storage with causality tracking, conversation management, replay capability, and audit traceability.

It explicitly supports conversation grouping via `subject`, and shows retrieving a conversation’s signals “in chronological order.”

It also includes explicit “Event Sourcing Pattern” examples (record events then rebuild state via replay), which can serve as the conceptual foundation for your “conversation state = reduce(events)” requirement.

### Dispatch and observability hooks already exist

`Jido.Signal.Dispatch` supports multiple delivery adapters. For observability and external streaming, the PubSub adapter broadcasts via `Phoenix.PubSub` topics, enabling distributed fan-out to UIs or monitoring processes.

For external integrations, the webhook dispatch adapter supports signature headers/retry policies/event-type mapping.

Dispatch includes a circuit breaker wrapper emitting telemetry events (useful for operational monitoring in a system that dispatches to unreliable destinations).

Finally, Jido provides `BusSpy` as a telemetry-based test utility for observing signals crossing boundaries, which is directly aligned with the “observe event streams” requirement from a testability perspective.

### Jido.Messaging as a channel adapter and persistence boundary for human-facing chat

The `jido_messaging` repository positions itself as a messaging/notification system with a unified interface across channels (Telegram/Discord/Slack/etc.), and an LLM-ready role-based message design (`:user | :assistant | :system | :tool`) with delivery/read status.

This is a natural “edge adapter” layer for your event-based conversation core: it can ingest external messages and deliver assistant messages, while your conversation engine remains channel-agnostic.

## Proposed architecture overview

The recommended architecture treats “conversation” as an event-sourced aggregate with a deterministic reducer, surrounded by a signal bus for distribution and a journal for durability/traceability. The design goal is: **the conversation engine never blocks on long-running work; it only applies events and emits directives (effects)**, which in turn generate more events.

Illustrative diagrams: event sourcing architecture, Elixir GenStage pipeline, and CloudEvents specification.

### Core components

**Ingress adapters (multiple sources)**
Adapters normalize external stimuli into `Jido.Signal`:

- Messaging ingress (from Jido.Messaging channel handlers).
- Tool runtime ingress (tool started/progress/result/error).
- LLM runtime ingress (generation started/token delta/completed/refusal/error).
- User control ingress (abort/cancel, “stop generation,” “retry,” “edit last message”).
- Time/scheduler ingress (timeouts, debounce windows, maintenance ticks).

Jido calls “Sensors” event producers that dispatch signals back to a parent agent; this is a good mental model for many of these ingress adapters (tool monitors, timeouts, etc.).

**Signal journal (durable event log + causality + conversation grouping)**
Every normalized signal is recorded in a `Jido.Signal.Journal` (ETS/Mnesia/etc.) with:

- `subject` as the conversation identifier (or a stable conversation/topic key).
- Optional `cause_id` for derived events (tool result causes, “assistant message completed” caused by “user prompt received,” etc.).

**Signal bus (distribution + backpressure-ish controls + replay + subscription)**
Signals are published to a `Jido.Signal.Bus` that:

- Routes by dot-notation patterns (via the router abstraction).
- Supports persistent subscription with ack/checkpoints/DLQ and configurable in-flight/pending limits.
- Offers replay/snapshots over the internal log (helpful for diagnostics and recovery flows).

**Conversation runtime (partitioned reducers + effect runtime)**
This is your “event queue processor” layer. It consumes conversation-related signals, prioritizes them, applies them to conversation state, and emits directives which start long-running work or publish downstream signals.

There are two viable shapes:

1. **Partitioned conversation workers (recommended default)**
   A fixed number of workers (partitions) each manage many conversations, chosen via consistent hashing on `conversation_id`. This avoids “one persistent bus subscriber per conversation,” which can become problematic given that persistent subscriptions are handled by the main bus process.

2. **One process per conversation (works at smaller scale)**
   A dynamic supervisor per conversation, but you should typically avoid giving each conversation its own persistent subscription to the Bus for scaling reasons noted above.

**Conversation state representation (event-sourced + projections)**
Use either (or both) of:

- `Jido.Thread` as the canonical, immutable conversation log for “LLM context projections.”
- A reducer state (agent state) that includes tool call map, running LLM step(s), user/session preferences, policy flags, and pointers to persisted artifacts.

Jido’s deterministic `cmd/2` contract (state transitions separated from directives) is the basis for reliable replays, audits, and testability.

**Observability fan-out**
Events are observable through:

- Direct Bus subscriptions (internal tools/monitors).
- Dispatch adapters (PubSub/Logger/Webhook/HTTP) for UI streaming, logs, or external monitoring.
- Telemetry events from dispatch circuit breakers and bus rate limiting.

## Event contract and stream taxonomy

### Canonical envelope: CloudEvents with Jido extensions

Adopt `Jido.Signal` as the single envelope type for all event sources and internal actions.

Core fields you should treat as mandatory at the framework boundary:

- `type`: dot-notation classification (e.g., `"conversation.prompt.received"`).
- `source`: origin (e.g., `"/messaging/telegram"`, `"/llm/provider_x"`, `"/tool/fs"`).
- `id`: unique identifier.
- `subject`: conversation id / correlation id (critical for conversation grouping and routing).

The journal explicitly treats subject as a conversation grouping mechanism (“conversation management”), so using `subject` as your canonical `conversation_id` aligns your architecture with existing Jido.Signal.Journal capabilities.

### Required “streams” as first-class type prefixes

To make observability and subscriptions clean, define stream prefixes (type namespaces). For example:

- `conv.in.*` — raw ingress normalized into signals (from user/messages/tools/LLM).
- `conv.applied.*` — acknowledgable “event applied” markers (useful for debugging and replay checkpoints).
- `conv.effect.*` — directives/effects started/completed (LLM call started, tool call started, etc.).
- `conv.out.*` — user-facing output deltas/final messages (message chunks, tool status updates for UI).
- `conv.audit.*` — compliance/security/audit-specific snapshots.

This leverages the router/bus wildcard patterns like `"audit.**"` and priority mechanisms at the routing layer (for handler selection and cross-cutting concerns).

### Causality and conversation linkage

A practical event-based conversation engine needs explicit cause/effect edges:

- User prompt received → causes LLM planning started.
- LLM tool call requested → causes tool started/progress/result.
- Tool result → causes LLM continuation or final answer.

The journal supports recording causality and tracing chains of effects/causes, which is directly valuable for debugging “why did the agent do that?” investigations.

## Ordering, prioritization, and cancellation semantics

### Ordering: distinguish “record order” from “processing order”

The journal is the canonical record of what happened, and it can return all signals in a conversation chronologically.

However, your requirement includes **priority-based processing**, which implies you may not always process strictly in arrival order (especially under load from high-volume events like token deltas). The key is to make your processing rule explicit and replayable:

- Record every event in journal insertion order (immutable).
- In the conversation runtime, apply a deterministic scheduling function `schedule(events, state)` that chooses the next event to apply based on priority and causal readiness (cause recorded, constraints satisfied).

This preserves auditability (“what arrived when”) while enabling responsiveness (“what we chose to handle next”). The journal already includes patterns and examples that support event-sourcing rebuilds, including rebuilding state via replay.

### Priority model: control-plane vs data-plane

A typical priority scheme that matches your event sources:

- **P0 (interrupt/control-plane):** abort/cancel, “stop generation,” revoke tool permissions, terminate child processes.
- **P1 (state-critical):** user prompts, tool results/errors, LLM step completion, policy decision events.
- **P2 (state-informative):** tool started/stopped, tool progress updates, LLM started.
- **P3 (high-volume/low-criticality):** token deltas, partial thoughts (if any), progress heartbeat ticks.

This lets the runtime remain responsive even if token deltas arrive faster than you can apply them.

### Cancellation: never block the reducer

The single biggest architectural lever for “abort works instantly” is: **never perform long-running work inside the conversation reducer process**.

Instead:

- Apply an event, update state, emit directives to spawn long work.
- The long work reports progress/results back as signals.
- An abort event cancels in-flight workers (by stopping child agents/processes or sending cancellation signals).

Jido’s orchestration guidance shows explicit cancellation patterns (`Jido.cancel/2` on in-flight work, plus “StopChild” directives for graceful shutdown of tracked children).

### Backpressure and overload behavior

For the external-facing bus subscription boundary, use persistent subscriptions when you need at-least-once delivery with checkpoints and DLQ. The bus exposes `max_in_flight` (unacknowledged) and `max_pending` (queued) limits, which can serve as your first layer of system pressure control.

Design implication: your conversation runtime should ack only after it has durably recorded and/or applied events (depending on your durability needs), and should treat “event applied” markers (`conv.applied.*`) as an operational invariant.

## GenStage suitability analysis

### What GenStage gives you (and what it does not)

GenStage is a demand-driven event exchange behavior with built-in backpressure semantics: consumers send demand upstream and producers emit no more than demanded.

It also supports multiple producers and multiple consumers, but demand is tracked per producer and per consumer relationship—meaning there is **no inherent global ordering across multiple upstream sources** unless you explicitly create an aggregation stage that merges sources into a single ordered stream.

Dispatcher options matter:

- `GenStage.DemandDispatcher` (default): dispatches batches to the consumer with the biggest demand in FIFO ordering.
- `GenStage.PartitionDispatcher`: dispatches events according to partitions, with a configurable hash function that can choose partition based on event content; consumers subscribe to partitions explicitly.
- `GenStage.BroadcastDispatcher`: broadcast patterns (less relevant for a single ordered queue, more for fan-out).

What GenStage does *not* natively provide (but your requirements call for):

- Durable event journal with causality and conversation grouping (you’d build/bolt on a store).
- Built-in DLQ, checkpointing semantics, and replay (again: you’d build it).
- A standardized CloudEvents-compatible envelope (you’d define your own, unless you keep using `Jido.Signal` anyway).

In other words: GenStage is excellent for *in-memory processing pipelines*, but Jido.Signal already provides a bus + journal that cover many “message bus + event sourcing” concerns at the framework level.

### Where GenStage can still fit well in your architecture

If you want GenStage in the system, the best fit is **inside** the conversation runtime, not as a replacement for Jido.Signal Bus/Journal.

Two realistic integration patterns:

**Pattern A: GenStage as the internal scheduler/partitioner behind a small number of bus subscribers**
- One (or a small pool of) persistent Bus subscriber process(es) receives conversation signals.
- That process pushes signals into a GenStage producer that maintains an internal priority queue and exposes demand-driven consumption.
- Use `GenStage.PartitionDispatcher` with a `:hash` function that partitions by `conversation_id` (likely your signal `subject`) so all events for the same conversation land in the same partition consumer.
- Each partition consumer(s) runs the reducer for many conversations (state in ETS or a per-partition map), emitting directives and publishing new signals back to the bus.

This gives you: parallelism across conversations, bounded work via demand, and a natural place to implement priority scheduling (in producer).

**Pattern B: GenStage only for high-volume substreams (token deltas/progress)**
For streaming LLM output, you may receive huge volumes of “delta” events. A small, dedicated GenStage pipeline can handle:
- Coalescing/deduplication (“only keep the latest N deltas per conversation per 50ms”).
- Prioritized drop policies under load.
- Demand-driven UI fan-out.

In this pattern, the canonical record still lives in `Thread`/Journal; GenStage is purely a *delivery-quality optimization layer*.

### Why Broadway is relevant (but not necessarily your main tool)

Broadway is built on GenStage and emphasizes production-grade pipeline behaviors like batching, fault tolerance, and automatic acknowledgements.
If you were building a large-scale ingestion system where “conversation events” are analogous to queue messages (Kafka/SQS/etc.), Broadway would be a strong default.

But in your case, Jido.Signal.Bus already has persistent subscription semantics (ack, checkpointing, DLQ) and partitions, which overlap with Broadway’s “pipeline reliability” value proposition.
So the main argument for Broadway/GenStage is **in-memory throughput and scheduling control**, not “we need an event bus.”

## Observability, replay, and scaling considerations

### Pub-sub observability and multiple event streams

Jido.Signal provides several ways to expose event streams:

- Subscribe directly to the bus by type pattern (e.g., `conv.**`), and dispatch to a PID (local stream).
- Dispatch to `Phoenix.PubSub` topics for UI streaming and distributed consumers; Jido’s PubSub adapter explicitly wraps `Phoenix.PubSub.broadcast/3`.
- Dispatch to logger (structured/unstructured) for “always-on” debugging and audit trails.
- Dispatch to webhooks for external audit/monitoring integrations.

This fulfills the “different event stream can be subscribed to” requirement without inventing a new mechanism: streams become conventions over `type` namespaces + dispatch targets.

### Telemetry: treat it as a first-class companion stream

Two concrete telemetry sources in the Jido.Signal stack are directly relevant:

- Dispatch circuit breaker emits telemetry events for failures/rejections/resets.
- Bus partitions can rate-limit and emit telemetry when signals are rate limited.

Additionally, BusSpy demonstrates a telemetry-based approach to observing cross-process signal delivery in tests—useful for validating the correctness of your event-driven conversation core under concurrency.

### Replay, audits, and “why did the agent do that?”

Your event-based design becomes significantly more valuable if you lean into journal features:

- Trace cause/effect chains for a specific signal.
- Retrieve all signals for a conversation (subject) in chronological order.
- Rebuild conversation state by replaying events (explicitly shown in the journal’s event-sourcing examples).

For production operations, this is the difference between “the agent did something weird” and “we can prove what input triggered which tool, which produced which output, and what state transitions occurred.”

### Scaling strategy: partitions and subscription topology

Key scaling constraints/choices:

- Persistent subscriptions provide reliability features (ack/checkpoint/DLQ) but are handled by the main bus process “to honor backpressure,” so you should avoid “thousands of persistent subscribers (one per conversation)” as a default architecture.
- Use partition workers for high-throughput non-persistent subscription dispatch and consider keeping the conversation runtime as a small number of subscribers that do internal partitioning.
- Journal adapter choice matters: ETS for fast local persistence; Mnesia for durable clustered deployments; the journal guide explicitly describes Mnesia as suited for production durability/cluster use.
- Checkpoint semantics are described as “typically a Unix timestamp derived from UUID7 signal log IDs,” which can support robust resumption strategies if you align your processing checkpoints with journal/bus semantics.

### Integrating Jido.Messaging cleanly

Treat Jido.Messaging as the “channel boundary” and persistence mechanism for user-visible chat artifacts:

- Incoming channel messages are persisted as `JidoMessaging.Message` with role/content/status fields, then emitted as `conv.in.message` signals into the conversation bus/journal.
- Outgoing assistant text/tool messages are produced by the conversation runtime as events, persisted back into messaging storage, then delivered via channel adapters.

This preserves channel-agnosticism (your core reducer doesn’t care whether the source was Telegram or a local IDE plugin) while enabling per-channel delivery semantics and message lifecycle status tracking.