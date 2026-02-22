# 04. Runtime Effects and Cancellation

The reducer stays pure and emits directives. Effect execution is handled by the
runtime effect manager and workers.

## How effects are started

Reducer behavior (default flow):

- `conv.in.message.received` starts an LLM generation effect
- `conv.in.timer.tick` starts a timer effect
- control abort/stop events emit cancel directives for in-flight effects

## Effect classes

- `:llm`
- `:tool`
- `:timer`

Policy defaults come from `effect_runtime` config and can be overridden per
inbound event via `data.effect_policy`.

## Per-event effect controls

You can send effect runtime hints in inbound data:

```elixir
%{
  effect_policy: %{max_attempts: 4, backoff_ms: 150, timeout_ms: 8_000},
  simulate_effect: %{response: "synthetic test path"}
}
```

`simulate_effect` is useful in tests and controlled environments.

## Canceling active effects

Use the control adapter to request conversation cancellation:

```elixir
alias JidoConversation.Ingest.Adapters.Control

:ok =
  Control.ingest_abort(
    "conv-123",
    "ctrl-1",
    %{reason: "user_cancel"}
  )
```

This emits `conv.in.control.abort_requested`, which the reducer maps to
`cancel_effects` directives.

## Effect lifecycle streams

Effect workers emit lifecycle events in `conv.effect.*` namespaces, for example:

- `conv.effect.llm.generation.started`
- `conv.effect.llm.generation.progress`
- `conv.effect.llm.generation.completed`
- `conv.effect.llm.generation.failed`
- `conv.effect.llm.generation.canceled`

These lifecycle events are what power retry telemetry, projection output, and
replay diagnostics.
