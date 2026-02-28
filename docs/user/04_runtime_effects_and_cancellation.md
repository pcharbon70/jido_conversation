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

## Managed conversation process API

For request/response style host integrations, you can drive conversations
through managed runtime processes:

```elixir
{:ok, _pid, _status} =
  JidoConversation.ensure_conversation(conversation_id: "conv-123")

{:ok, _conversation, _directives} =
  JidoConversation.configure_skills("conv-123", ["web_search", "code_exec"])

{:ok, _conversation, _directives} =
  JidoConversation.send_user_message("conv-123", "Hello")

# Optional: append assistant output produced by your host integration
{:ok, _conversation, _directives} =
  JidoConversation.record_assistant_message("conv-123", "Hello from external runtime")

{:ok, context} =
  JidoConversation.conversation_llm_context("conv-123", max_messages: 10)

{:ok, generation_ref} =
  JidoConversation.generate_assistant_reply("conv-123")

receive do
  {:jido_conversation, {:generation_result, ^generation_ref, {:ok, result}}} ->
    result
end

# Cancel when needed
:ok = JidoConversation.cancel_generation("conv-123", "user_cancel")
```

Use this API when you want managed per-conversation processes and direct async
notifications. Keep using ingest adapters when your host app is event-source
driven and journal-first at all boundaries.

## Synchronous turn helper

For simple request/response flows, use `send_and_generate/3`:

```elixir
{:ok, conversation, result} =
  JidoConversation.send_and_generate("conv-123", "Hello", 
    generation_opts: [llm: %{backend: :jido_ai}],
    await_opts: [timeout_ms: 30_000]
  )
```

If you need explicit control, call `generate_assistant_reply/2` and then
`await_generation/3` directly. By default, `await_generation/3` cancels the
in-flight generation on timeout with reason `"await_timeout"`.
