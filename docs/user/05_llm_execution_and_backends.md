# 05. LLM Execution and Backends

`jido_conversation` has a unified LLM execution path with pluggable backends.

## Built-in backend modes

- `:jido_ai`: direct provider/model execution via JidoAI adapter
- `:harness`: coding CLI execution via Harness adapter

## Base config

```elixir
config :jido_conversation, JidoConversation.EventSystem,
  llm: [
    default_backend: :jido_ai,
    default_stream?: true,
    default_timeout_ms: 30_000,
    default_provider: "anthropic",
    default_model: "anthropic:claude-sonnet-4-5",
    backends: [
      jido_ai: [
        module: JidoConversation.LLM.Adapters.JidoAI,
        stream?: true,
        timeout_ms: 20_000,
        provider: "anthropic",
        model: "anthropic:claude-sonnet-4-5"
      ],
      harness: [
        module: JidoConversation.LLM.Adapters.Harness,
        stream?: true,
        timeout_ms: 60_000,
        provider: "codex",
        options: [harness_provider: :codex]
      ]
    ]
  ]
```

## Override precedence

Resolution order is deterministic:

1. effect-level overrides
2. conversation defaults
3. application config defaults

Supported fields:

- `backend`
- `module`
- `provider`
- `model`
- `stream?`
- `timeout_ms`
- `options`

## Per-message overrides

You can pass conversation defaults and per-request LLM overrides inside inbound
message data:

```elixir
%{
  conversation_defaults: %{
    llm: %{
      backend: :jido_ai,
      provider: "anthropic",
      model: "anthropic:claude-sonnet-4-5"
    }
  },
  llm: %{
    model: "anthropic:claude-opus-4-1",
    timeout_ms: 45_000,
    options: %{temperature: 0.2}
  }
}
```

## Retry and classification model

LLM errors are normalized into categories used by telemetry and retry policy,
including:

- `provider`
- `timeout`
- `transport`
- `auth`
- `config`
- `canceled`
- `unknown`

Non-retryable classes (for example auth/config) fail fast. Retryable classes
(for example timeout/transport) emit retrying progress lifecycle events and
increment retry-category telemetry.
