# Phase 4 deterministic runtime scheduler and reducer completion

## Scope completed

- Added deterministic scheduler core:
  - `JidoConversation.Runtime.Scheduler`
- Added pure reducer core:
  - `JidoConversation.Runtime.Reducer`
- Upgraded partition runtime worker to execute scheduler + reducer loop:
  - `JidoConversation.Runtime.PartitionWorker`
- Implemented queue-entry sequencing and deterministic dequeue policy:
  1. Causal readiness (`cause_id` must already be applied)
  2. Priority class selection (`P0..P3`)
  3. FIFO within priority by scheduler sequence
  4. Fairness threshold to avoid lower-priority starvation
- Added reducer-driven state transitions per conversation:
  - applied event count
  - stream family counters
  - control flags (abort requested)
  - in-flight effect lifecycle map
  - last event snapshot and bounded history
- Added reducer directives for `conv.applied.*` emission and executed them through ingestion pipeline.
- Added partition worker background draining continuation to avoid partial-drain starvation when queue work exceeds one drain step budget.
- Updated ingress subscriber ack behavior to support both persistent payload shapes:
  - `{:signal, {signal_log_id, signal}}` (direct log-id ack)
  - `{:signal, signal}` (log-id resolution from persistent in-flight state + ack)
- Preserved loop prevention by ignoring inbound `conv.applied.*` in runtime ingress processing.

## Integration adjustments

- Ingestion pipeline continues to attach `cause_id` in signal extensions before journal/publish.
- Pipeline tests were updated to assert original event identity and dedupe behavior without assuming conversation streams contain only one event (runtime now emits matching `conv.applied.*` companions).

## Test coverage added

- `test/jido_conversation/runtime/scheduler_test.exs`
  - priority model
  - causal readiness
  - FIFO ordering
  - fairness threshold behavior
- `test/jido_conversation/runtime/reducer_test.exs`
  - state updates
  - directive emission
  - in-flight effect lifecycle transitions
  - no nested applied directives for `conv.applied.*`
  - abort flag transition
- `test/jido_conversation/runtime/partition_worker_test.exs`
  - cause-before-dependent ordering
  - runtime emission of `conv.applied` markers through ingestion replay

## Quality gates

- `mix test`
- `mix credo --strict`
- `mix dialyzer`
