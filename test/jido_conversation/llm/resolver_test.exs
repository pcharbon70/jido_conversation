defmodule JidoConversation.LLM.ResolverTest do
  use ExUnit.Case, async: true

  alias JidoConversation.LLM.Error
  alias JidoConversation.LLM.Resolver

  defmodule JidoAIBackend do
  end

  defmodule HarnessBackend do
  end

  test "resolve/3 applies deterministic precedence across sources" do
    effect_overrides = %{
      llm: %{
        model: "effect-nested-model",
        options: %{max_tokens: 600}
      },
      model: "effect-model",
      stream?: false
    }

    conversation_defaults = %{
      llm: %{
        backend: :jido_ai,
        provider: "conversation-provider",
        timeout_ms: 8_000,
        options: %{temperature: 0.7}
      }
    }

    assert {:ok, resolved} =
             Resolver.resolve(effect_overrides, conversation_defaults, llm_config())

    assert resolved.backend == :jido_ai
    assert resolved.module == JidoAIBackend
    assert resolved.provider == "conversation-provider"
    assert resolved.model == "effect-model"
    assert resolved.stream? == false
    assert resolved.timeout_ms == 8_000
    assert resolved.sources.backend == :conversation

    assert resolved.options == %{
             temperature: 0.7,
             top_p: 0.95,
             max_tokens: 600
           }
  end

  test "resolve/3 falls back to app defaults when no overrides are present" do
    llm_config =
      llm_config(
        default_backend: :harness,
        default_provider: "anthropic",
        default_model: "claude-opus-4",
        backends: [harness: [module: HarnessBackend, stream?: true, options: [mode: "cli"]]]
      )

    assert {:ok, resolved} = Resolver.resolve(%{}, %{}, llm_config)
    assert resolved.backend == :harness
    assert resolved.module == HarnessBackend
    assert resolved.provider == "anthropic"
    assert resolved.model == "claude-opus-4"
    assert resolved.stream? == true
    assert resolved.options == %{mode: "cli"}
    assert resolved.sources.backend == :config
  end

  test "resolve/3 returns config error when backend module is not available" do
    llm_config =
      llm_config(backends: [jido_ai: [module: JidoConversation.LLM.Adapters.DoesNotExist]])

    assert {:error, %Error{} = error} = Resolver.resolve(%{}, %{}, llm_config)
    assert error.category == :config
    assert error.retryable? == false
    assert error.message == "llm backend module is not available"
  end

  test "resolve/3 rejects invalid nested llm override payloads" do
    assert {:error, %Error{} = error} = Resolver.resolve(%{llm: "not-a-map"}, %{}, llm_config())

    assert error.category == :config
    assert error.message == "invalid llm overrides payload"
    assert error.details.source == :"effect.llm"
  end

  defp llm_config(overrides \\ []) do
    Keyword.merge(
      [
        default_backend: :jido_ai,
        default_stream?: true,
        default_timeout_ms: 30_000,
        default_provider: nil,
        default_model: "gpt-4.1",
        backends: [
          jido_ai: [
            module: JidoAIBackend,
            stream?: true,
            timeout_ms: 20_000,
            provider: "openai",
            model: "gpt-4.1-mini",
            options: [temperature: 0.2, top_p: 0.95]
          ],
          harness: [
            module: HarnessBackend,
            stream?: false,
            timeout_ms: 60_000,
            provider: nil,
            model: nil,
            options: [mode: "cli"]
          ]
        ]
      ],
      overrides,
      fn
        :backends, defaults, backends_override when is_list(backends_override) ->
          Keyword.merge(defaults, backends_override, fn _backend,
                                                        backend_defaults,
                                                        backend_override ->
            Keyword.merge(backend_defaults, backend_override)
          end)

        _key, _default, override ->
          override
      end
    )
  end
end
