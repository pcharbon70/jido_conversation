# Phase 3 journal-first ingress pipeline completion

## Scope completed

- Added a centralized journal-first ingestion runtime:
  - `JidoConversation.Ingest.Pipeline`
- Implemented ingestion flow at one boundary:
  1. Normalize/validate contract
  2. Deduplicate by `{subject, id}`
  3. Append to journal with optional `cause_id`
  4. Publish to signal bus
- Added dedupe state management with bounded cache size (`ingestion_dedupe_cache_size`).
- Added ingestion query APIs for:
  - conversation events
  - causal chain traces
  - bus replay access
- Added a public ingestion facade: `JidoConversation.Ingest`.
- Added ingress adapters for major event-source categories:
  - messaging
  - tool lifecycle
  - llm lifecycle
  - control plane
  - timer/scheduler
- Wired ingestion pipeline into app supervision tree.
- Updated runtime ingress subscriber to support persistent subscription payload form and acknowledge processed signals.

## Configuration added

- `ingestion_dedupe_cache_size` under `JidoConversation.EventSystem`

## Test coverage added

- Pipeline integration tests:
  - journal + publish path
  - dedupe behavior
  - cause/effect chain linking
  - contract-rejection path
- Adapter integration tests across all source categories.

## Deferred to later phases

- Journal-backed stranded-event recovery/re-drive flow for publish failures
- Full ingest idempotency restoration across process restarts
- Rich adapter-level schema validation and per-source normalization policies
- Reducer scheduling semantics and effect orchestration
