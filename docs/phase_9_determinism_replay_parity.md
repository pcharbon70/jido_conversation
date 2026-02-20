# Phase 9 determinism replay parity hardening

## Scope completed

- Added replay-vs-live determinism coverage for sampled conversations.
- Added projection parity checks between:
  - live projection facade output
  - projections rebuilt from replayed event streams

## Validation coverage

- Added `test/jido_conversation/determinism_test.exs`:
  - replays recorded stream events through scheduler + reducer and compares final
    state against live partition snapshot for the same conversation
  - verifies timeline and LLM-context projections match when reconstructed from replayed events

## Files added/updated

- Added:
  - `test/jido_conversation/determinism_test.exs`
  - `docs/phase_9_determinism_replay_parity.md`
- Updated:
  - `README.md`
  - `notes/research/events_based_architecture_implementation_plan.md`

## Quality gates

- `mix format`
- `mix test`
- `mix credo --strict`
- `mix dialyzer`
