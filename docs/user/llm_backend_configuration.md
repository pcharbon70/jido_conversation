# LLM Backend Configuration

This guide explains how to configure backend selection, provider/model routing,
and per-request overrides for LLM effects.

## 1. Configure LLM backends

Set the `llm` block under `JidoConversation.EventSystem`:

```elixir
import Config

config :jido_conversation, JidoConversation.EventSystem,
  llm: [
    default_backend: :jido_ai,
    default_stream?: true,
    default_timeout_ms: 30_000,
    default_provider: "anthropic",
    default_model: "claude-sonnet",
    backends: [
      jido_ai: [
        module: JidoConversation.LLM.Adapters.JidoAI,
        stream?: true,
        timeout_ms: 20_000,
        provider: "anthropic",
        model: "claude-sonnet",
        options: [llm_client_module: Jido.AI.LLMClient]
      ],
      harness: [
        module: JidoConversation.LLM.Adapters.Harness,
        stream?: true,
        timeout_ms: 60_000,
        provider: "codex",
        model: "harness-default",
        options: [harness_module: Jido.Harness, harness_provider: :codex]
      ]
    ]
  ]
```

Notes:

- `default_backend` chooses the runtime path (`:jido_ai` or `:harness`).
- `module` under each backend must be loadable in the host runtime.
- `provider`/`model` values are advisory defaults for resolution.

## 2. Override precedence

Resolver precedence is deterministic:

1. Effect overrides
2. Conversation defaults
3. App config defaults

Supported override fields:

- `backend`
- `module`
- `provider`
- `model`
- `stream?`
- `timeout_ms`
- `options`

Overrides can be top-level or nested under `llm`.

## 3. Pass conversation defaults and effect overrides

You can pass conversation defaults and request-level overrides in inbound event
payloads.

```elixir
JidoConversation.ingest(%{
  type: "conv.in.message.received",
  source: "/app/chat",
  subject: "conv-123",
  data: %{
    message_id: "msg-1",
    ingress: "web",
    text: "Summarize this file",
    conversation_defaults: %{
      llm: %{
        backend: :jido_ai,
        provider: "anthropic",
        model: "claude-sonnet",
        timeout_ms: 15_000
      }
    },
    llm: %{
      model: "claude-opus",
      options: %{temperature: 0.2}
    }
  },
  extensions: %{contract_major: 1}
})
```

## 4. JidoAI vs Harness behavior

- `:jido_ai` path:
  - provider/model selection is controlled by this library configuration and
    overrides.
  - use this path for direct provider/model routing.
- `:harness` path:
  - coding CLI typically owns provider/model at execution time.
  - use backend `options` for harness-specific controls (`cwd`, tool allowlists,
    harness provider, transport, and similar runtime flags).

## 5. Validate runtime behavior

Use these APIs to validate effective behavior:

- `JidoConversation.timeline/2`
- `JidoConversation.llm_context/2`
- `JidoConversation.telemetry_snapshot/0`

For operations details, see `docs/user/operations_and_host_integration.md`.
