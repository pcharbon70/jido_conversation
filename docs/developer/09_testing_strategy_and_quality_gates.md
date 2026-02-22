# 09. Testing Strategy and Quality Gates

The test suite is structured to protect determinism, reliability, and contract
stability.

## Test layers

1. Unit tests
   - signal contract
   - LLM domain model and resolver
   - projections
   - telemetry aggregation

2. Runtime component tests
   - scheduler
   - reducer
   - coordinator
   - effect manager/worker behavior

3. Matrix/parity suites
   - LLM retry policy (non-stream and stream)
   - cancellation telemetry parity
   - retry category telemetry parity

4. System hardening suites
   - determinism and reliability tests
   - replay stress tests

## Key test directories

- `test/jido_conversation/signal/`
- `test/jido_conversation/ingest/`
- `test/jido_conversation/runtime/`
- `test/jido_conversation/llm/`
- `test/jido_conversation/projections/`

## Quality gate

Pre-commit runs:

- `mix test`
- `mix credo --strict`
- `mix dialyzer`

## Contributor expectations

- Add tests for any contract, reducer, effect, or projection behavior change.
- Prefer focused matrix additions for retry/cancellation classification changes.
- Keep flaky timing assumptions out of tests; use eventual assertions where
  needed.
