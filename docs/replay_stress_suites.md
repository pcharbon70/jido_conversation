# Replay Stress Suites

## Scope completed

- Added replay-stress coverage for larger sampled traces.
- Validated full replay recovery for high-count audit streams.
- Validated projection reconstruction from replayed large output traces.

## Validation coverage

- Added `test/jido_conversation/replay_stress_test.exs`:
  - `large audit traces remain fully replayable by stream pattern`
    - ingests a large `conv.audit.*` trace for one conversation
    - asserts replay includes the full ingested trace id set
  - `large replayed output traces reconstruct timeline and llm context projections`
    - ingests high-volume `conv.out.*` deltas/status/completed events
    - replays output stream and reconstructs timeline + LLM context projections
    - asserts parity with live projection facade outputs

## Quality gates

- `mix format --check-formatted`
- `mix test`
- `mix credo --strict`
- `mix dialyzer`
