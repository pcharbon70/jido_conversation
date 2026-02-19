# Phase 2 event contract and validation boundary completion

## Scope completed

- Implemented canonical signal normalization/validation boundary:
  - `JidoConversation.Signal.Contract`
- Added contract validation rules for framework boundaries:
  - Required envelope fields: `type`, `source`, `id`, `subject`
  - Supported stream namespaces:
    - `conv.in.*`
    - `conv.applied.*`
    - `conv.effect.*`
    - `conv.out.*`
    - `conv.audit.*`
  - Contract version policy:
    - Uses `extensions.contract_major`
    - Supported majors: `[1]`
  - Stream-specific payload requirements
- Added normalization aliases for ingress adapters:
  - `conversation_id` -> `subject`
  - top-level `contract_major` -> `extensions.contract_major`
- Wired runtime ingress subscription through contract validation before enqueueing.
- Added comprehensive positive/negative tests for malformed and unsupported signals.

## Validation coverage added

- Valid map normalization
- Alias normalization (`conversation_id` and `contract_major`)
- Pre-built signal validation pass-through
- Missing required subject rejection
- Unsupported type namespace rejection
- Missing contract version rejection
- Unsupported contract major rejection
- Non-map payload rejection
- Missing required payload keys rejection

## Deferred to later phases

- Contract schema evolution automation and migration tooling
- Journal-first ingest implementation and idempotency strategy
- Reducer/scheduler application semantics and replay parity checks
- Effect runtime cancellation and retry orchestration
