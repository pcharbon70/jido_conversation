# 09. API Surfaces and Selection

`jido_conversation` exposes two API surfaces that serve different integration
styles.

## API surfaces

1. `JidoConversation` (managed runtime facade)

- Best when your host app wants process management, runtime health checks,
  event ingestion, and projection/replay queries.
- Works with conversation locators (`conversation_id` or `{project_id,
  conversation_id}`) and can start/stop managed conversation processes.
- Primary functions:
  - `JidoConversation.ensure_conversation/1`
  - `JidoConversation.send_user_message/3`
  - `JidoConversation.generate_assistant_reply/2`
  - `JidoConversation.await_generation/3`
  - `JidoConversation.ingest/2`
  - `JidoConversation.timeline/2`

2. `Jido.Conversation` (agent-first in-memory conversation)

- Best when you already manage agents directly and want an in-memory,
  append-only `Jido.Thread` journal with derived state helpers.
- Operates on a `%Jido.Agent{}` conversation struct and returns updated
  conversation values directly.
- Primary functions:
  - `Jido.Conversation.new/1`
  - `Jido.Conversation.send_user_message/3`
  - `Jido.Conversation.record_assistant_message/3`
  - `Jido.Conversation.generate_assistant_reply/2`
  - `Jido.Conversation.thread_entries/1`
  - `Jido.Conversation.derived_state/1`

## How they relate

- `JidoConversation` is the host-facing runtime façade.
- Managed runtime operations in `JidoConversation` use the same conversation
  semantics as `Jido.Conversation` through runtime wrappers.
- Both surfaces align on the same conversation concepts (messages, cancellation,
  LLM configuration, skills, derived state).

## Selection guidance

- Use `JidoConversation` if you need runtime supervision, locator-based access,
  projection/replay APIs, and health/telemetry integration.
- Use `Jido.Conversation` if you need a direct agent/thread object model inside
  an existing Jido agent workflow.
- If unsure, start with `JidoConversation` and move specific internal flows to
  `Jido.Conversation` only where direct agent composition is needed.
