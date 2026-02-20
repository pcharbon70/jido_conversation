# Testing Strategy

The test suite is organized around determinism, contract safety, and runtime
reliability.

## Test layers

### Contract and boundary tests

- `test/jido_conversation/signal/contract_test.exs`
- `test/jido_conversation/signal/contract_evolution_test.exs`
- `test/jido_conversation/ingest/pipeline_test.exs`

Focus:

- envelope validation
- stream payload requirements
- version compatibility behavior
- dedupe and ingest boundary correctness

### Runtime logic tests

- `test/jido_conversation/runtime/scheduler_test.exs`
- `test/jido_conversation/runtime/reducer_test.exs`
- `test/jido_conversation/runtime/partition_worker_test.exs`
- `test/jido_conversation/runtime/effect_manager_test.exs`

Focus:

- scheduler fairness and causal readiness
- reducer directives/state transitions
- applied marker/output emission
- effect lifecycle and cancellation semantics

### Projection and replay parity tests

- `test/jido_conversation/determinism_test.exs`
- `test/jido_conversation/replay_stress_test.exs`

Focus:

- replay-vs-live parity for state/projections
- larger sampled trace replay resilience

### Reliability tests

- `test/jido_conversation/reliability_test.exs`

Focus:

- burst traffic behavior
- queue pressure/backpressure handling
- eventual drain expectations

## Quality gates

Default quality checks:

- `mix format --check-formatted`
- `mix test`
- `mix credo --strict`
- `mix dialyzer`

Local shorthand:

```bash
mix quality
```

## Guidelines for new tests

- Prefer deterministic assertions over timing-sensitive expectations.
- For async-heavy flows, wait on runtime idle signals before final assertions.
- Use replay-based assertions for behavior that must remain reproducible.
- Keep test data explicit and include `contract_major` in generated signals.
