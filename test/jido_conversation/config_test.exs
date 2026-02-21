defmodule JidoConversation.ConfigTest do
  use ExUnit.Case, async: false

  alias JidoConversation.Config

  @app :jido_conversation
  @key JidoConversation.EventSystem

  defmodule HarnessBackend do
  end

  setup do
    previous = Application.get_env(@app, @key)

    on_exit(fn ->
      if is_nil(previous) do
        Application.delete_env(@app, @key)
      else
        Application.put_env(@app, @key, previous)
      end
    end)

    :ok
  end

  test "llm defaults are available in config accessors" do
    Application.delete_env(@app, @key)

    llm = Config.llm()

    assert llm[:default_backend] == :jido_ai
    assert llm[:default_stream?] == true
    assert llm[:default_timeout_ms] == 30_000
    assert Keyword.has_key?(llm[:backends], :jido_ai)
    assert Keyword.has_key?(llm[:backends], :harness)
  end

  test "llm config merges backend overrides while preserving defaults" do
    Application.put_env(@app, @key,
      llm: [
        default_backend: :harness,
        backends: [
          harness: [
            module: HarnessBackend,
            stream?: false,
            options: [mode: "cli"]
          ]
        ]
      ]
    )

    assert Config.llm_default_backend() == :harness
    assert Config.llm_backend_module(:harness) == HarnessBackend
    assert Config.llm_backend_config(:harness)[:stream?] == false
    assert Config.llm_backend_config(:harness)[:options] == [mode: "cli"]
    assert is_list(Config.llm_backend_config(:jido_ai))
  end

  test "validate! raises when llm default backend is not configured" do
    Application.put_env(@app, @key,
      llm: [
        default_backend: :missing,
        backends: [jido_ai: [module: nil], harness: [module: nil]]
      ]
    )

    assert_raise ArgumentError,
                 ~r/expected llm.default_backend :missing to exist in llm.backends/,
                 fn ->
                   Config.validate!()
                 end
  end
end
