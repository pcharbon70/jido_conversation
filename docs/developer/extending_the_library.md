# Extending the Library

Use this guide when adding behavior to the runtime.

For LLM adapter-specific extension rules, see:
`docs/developer/llm_backend_adapter_contract.md`.

## Add a new ingress event type

1. Define/confirm stream namespace and payload requirements in
   `JidoConversation.Signal.Contract`.
2. Add or update adapter helpers under `lib/jido_conversation/ingest/adapters/`.
3. Add reducer behavior (if state transition is needed).
4. Add projection behavior (if user/model views must include it).
5. Add tests:
   - contract acceptance/rejection
   - ingest pipeline behavior
   - reducer and projection behavior

## Add reducer behavior safely

When modifying `JidoConversation.Runtime.Reducer`:

- Keep it pure and deterministic.
- Do not perform blocking I/O or process interaction.
- Emit directives for side effects.
- Ensure `conv.applied.*` events still do not recurse into applied markers.

Recommended tests:

- reducer unit tests
- scheduler + reducer determinism parity
- replay stress parity when relevant

## Add a new effect class

Current effect classes are `:llm`, `:tool`, and `:timer`.

To add another class:

1. Extend reducer directive payload generation for the new class.
2. Extend `EffectManager` class validation.
3. Add policy defaults and validation in `JidoConversation.Config`.
4. Add lifecycle type mapping in effect manager/worker.
5. Add tests for start/retry/timeout/cancel behavior.

## Add a new projection

1. Implement projection module in `lib/jido_conversation/projections/`.
2. Use `Ingest.conversation_events/1` as canonical source.
3. Sort/filter consistently and document any options.
4. Add facade function if needed from `JidoConversation`.
5. Add parity tests using replay reconstruction where possible.

## Contract evolution guidance

- Keep `contract_major` compatibility explicit.
- Prefer additive payload evolution where possible.
- If adding required keys for an existing stream, treat it as a contract-major
  change and update tests/documentation accordingly.

Reference: `test/jido_conversation/signal/contract_evolution_test.exs`

## Common pitfalls

- Using non-UUIDv7 IDs for replay windows based on timestamp filters.
- Publishing directly to bus from random modules instead of the ingestion path.
- Introducing side effects into reducer logic.
- Adding high-volume outputs without considering backpressure/retry behavior.
