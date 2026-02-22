# 03. Contract and Ingestion Pipeline

This guide focuses on `Signal.Contract` and `Ingest.Pipeline` internals.

## Contract normalization

`JidoConversation.Signal.Contract` accepts `%Jido.Signal{}`, map, or keyword
input and normalizes aliases before validation.

Supported aliases:

- `conversation_id` -> `subject`
- top-level `contract_major` -> `extensions.contract_major`

## Contract validation checks

1. Required envelope fields: `type`, `source`, `id`, `subject`
2. Stream namespace prefix: `conv.in|applied|effect|out|audit.*`
3. Supported contract version: `extensions.contract_major == 1`
4. Stream-specific payload keys:
   - `in`: `message_id`, `ingress`
   - `applied`: `applied_event_id`
   - `effect`: `effect_id`, `lifecycle`
   - `out`: `output_id`, `channel`
   - `audit`: `audit_id`, `category`

## Ingest pipeline responsibilities

`JidoConversation.Ingest.Pipeline` owns the ingestion write boundary:

- normalize + validate signal
- apply dedupe policy
- append to journal
- publish to bus
- preserve optional `cause_id` relationships

## Adapter layer

Adapters in `JidoConversation.Ingest.Adapters.*` provide domain-oriented
helpers that produce valid canonical signal payloads for:

- messaging
- control
- timer
- tool lifecycle
- LLM lifecycle
- outbound events

## Failure modes

Common errors include:

- contract validation failures (`:payload`, `:field`, namespace/version errors)
- publish failures under backpressure
- duplicate IDs per `{subject, id}` dedupe key

Host integrations should use bounded retries around ingest calls when upstream
transport or bus pressure can spike.
