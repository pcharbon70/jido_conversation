# Scheduler Burst Fairness Hardening

## Scope completed

- Added burst-traffic fairness/load coverage for the partition scheduler.
- Verified bounded waiting for ready lower-priority events under sustained control-plane bursts.

## Validation coverage

- Updated `test/jido_conversation/runtime/scheduler_test.exs`:
  - validates bounded interval scheduling for ready lower-priority events during a burst
  - validates a lower-priority event is not forced to wait behind an entire large high-priority backlog
  - uses deterministic scheduler draining to avoid runtime timing flake

## Quality gates

- `mix format --check-formatted`
- `mix test`
- `mix credo --strict`
- `mix dialyzer`
