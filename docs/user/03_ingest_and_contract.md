# 03. Ingest and Contract

All signals pass through one contract gate before they enter runtime. This keeps
ingestion deterministic and protects projection/replay behavior.

## Minimum required envelope

Every signal must include:

- `type`
- `source`
- `subject` (conversation ID)
- `extensions.contract_major` (`1`)

Aliases:

- `conversation_id` is accepted and normalized to `subject`
- top-level `contract_major` is normalized to `extensions.contract_major`

## Required payload keys by stream family

- `conv.in.*`: `message_id`, `ingress`
- `conv.applied.*`: `applied_event_id`
- `conv.effect.*`: `effect_id`, `lifecycle`
- `conv.out.*`: `output_id`, `channel`
- `conv.audit.*`: `audit_id`, `category`

## Direct ingest example

```elixir
{:ok, _result} =
  Jido.Conversation.ingest(%{
    type: "conv.in.message.received",
    source: "/chat/ui",
    subject: "conv-123",
    data: %{
      message_id: "msg-1",
      ingress: "web",
      text: "Summarize this"
    },
    extensions: %{contract_major: 1}
  })
```

## Preferred adapters

Use adapters to reduce envelope mistakes:

- `Jido.Conversation.Ingest.Adapters.Messaging.ingest_received/5`
- `Jido.Conversation.Ingest.Adapters.Control.ingest_abort/4`
- `Jido.Conversation.Ingest.Adapters.Timer.ingest_tick/4`
- `Jido.Conversation.Ingest.Adapters.Llm.ingest_lifecycle/5`
- `Jido.Conversation.Ingest.Adapters.Tool.ingest_lifecycle/5`
- `Jido.Conversation.Ingest.Adapters.Outbound.*` helpers

## Causality and idempotency

- Pass `cause_id` in ingest opts when linking a derived event to a prior event.
- Dedupe uses `{subject, id}`; reuse of the same signal ID in the same
  conversation is treated as duplicate ingest.

## Replay/query APIs

- `Jido.Conversation.Ingest.conversation_events/1`
- `Jido.Conversation.Ingest.trace_chain/2`
- `Jido.Conversation.Ingest.replay/3`
