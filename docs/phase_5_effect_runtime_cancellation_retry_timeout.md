# Phase 5 effect runtime, lifecycle, cancellation, retry, and timeout

## Scope completed

- Added effect runtime configuration and policy accessors:
  - `effect_runtime` policy block for `:llm`, `:tool`, `:timer`
  - deep merge + validation in `JidoConversation.Config`
  - `JidoConversation.Config.effect_runtime_policy/1`
- Added dedicated effect runtime supervision:
  - `JidoConversation.Runtime.EffectSupervisor` (dynamic)
  - `JidoConversation.Runtime.EffectManager` (manager process)
- Added asynchronous effect execution worker:
  - `JidoConversation.Runtime.EffectWorker`
  - lifecycle emissions: `started`, `progress`, `completed`, `failed`, `canceled`
  - timeout handling
  - retry with exponential backoff
  - cancellation support
  - worker restart behavior set to `:temporary` to avoid unintended restarts
- Added manager orchestration for in-flight state and per-conversation cancellation:
  - start one worker per effect id
  - monitor/cleanup on completion or process down
  - `cancel_conversation/3` fan-out to worker cancellation
  - runtime stats (`in_flight_count`, ids, by-conversation index)
- Added reducer/runtime directive integration:
  - new directives: `:start_effect`, `:cancel_effects`
  - ingress mapping:
    - `conv.in.message.received` -> start LLM effect
    - `conv.in.timer.tick` -> start timer effect
    - `conv.in.control.abort_requested|stop_requested` -> cancel effects
  - partition worker execution paths for new directives
- Added safe cause-link fallback behavior for lifecycle ingestion:
  - if `cause_id` is missing from journal, lifecycle signals are ingested without cause linkage

## Integration adjustments

- `JidoConversation.Runtime.PartitionWorker.wait_for_runtime_idle!/0` test helper now waits for:
  - empty partition queues
  - zero in-flight effect workers
- Reducer helper clause ordering was normalized to remove compile warnings and keep static analysis clean.

## Test coverage added/updated

- Added `test/jido_conversation/runtime/effect_manager_test.exs`:
  - successful start -> started/progress/completed + cleanup
  - timeout -> retry and terminal failed event
  - cancellation -> canceled lifecycle + cleanup
  - invalid `cause_id` fallback still emits lifecycle events
- Updated reducer and partition worker tests to account for Phase 5 directives and effect-runtime idleness.

## Quality gates

- `mix test`
- `mix credo --strict`
- `mix dialyzer`
