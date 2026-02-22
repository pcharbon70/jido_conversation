# LLM Runtime Migration Notes

This note explains migration from the earlier simulated LLM effect behavior to
the unified backend-driven runtime path.

## What changed

Before unified adapters, `:llm` effects were runtime placeholders. They did not
execute real backend calls and had limited lifecycle/result semantics.

Now `:llm` effects execute through configured adapters:

- `Jido.Conversation.LLM.Adapters.JidoAI`
- `Jido.Conversation.LLM.Adapters.Harness`

## Migration impact

### 1. Configuration is required

Hosts must provide valid backend module wiring under:

- `config :jido_conversation, Jido.Conversation.EventSystem, llm: [...]`

If backend modules are missing or invalid, effects fail with `:config` errors.

### 2. Effect payloads are richer

`conv.effect.llm.generation.*` events now include normalized backend metadata
and result fields such as:

- `status`
- `provider`
- `model`
- `usage`
- `finish_reason`
- `metadata`

Do not assume old placeholder payload shapes.

### 3. Cancellation is backend-aware

`cancel_conversation/3` can now invoke adapter cancellation when execution refs
are available. Lifecycle and telemetry include cancellation result metadata.

### 4. Retry behavior uses error classification

Retries now depend on normalized error retryability:

- retryable errors may retry until policy limits
- non-retryable errors fail immediately

### 5. Observability surface expanded

`Jido.Conversation.telemetry_snapshot/0` now includes LLM-specific metrics:

- lifecycle counts
- backend-grouped lifecycle counts
- stream duration and chunk counts
- cancel latency/results
- retry categories

## Migration checklist

1. Configure `llm` backend modules and defaults in host config.
2. Update tests that asserted simulated LLM payload shapes.
3. Update any consumers of `conv.effect.llm.generation.*` to read normalized
   fields.
4. Validate projections from real backend traces:
   - `Jido.Conversation.timeline/2`
   - `Jido.Conversation.llm_context/2`
5. Update dashboards/alerts to include new LLM telemetry metrics.

## Verification commands

Run the standard quality gate after migration:

```bash
mix test
mix credo --strict
mix dialyzer
```
