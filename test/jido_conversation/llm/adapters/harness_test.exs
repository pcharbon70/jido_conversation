defmodule JidoConversation.LLM.Adapters.HarnessTest do
  use ExUnit.Case, async: true

  alias JidoConversation.LLM.Adapters.Harness
  alias JidoConversation.LLM.Error
  alias JidoConversation.LLM.Event
  alias JidoConversation.LLM.Request
  alias JidoConversation.LLM.Result

  defmodule TestHarness do
    def run(provider, prompt, opts)
        when is_atom(provider) and is_binary(prompt) and is_list(opts) do
      send(self(), {:run_with_provider, provider, prompt, opts})
      Keyword.get(opts, :test_result, {:ok, Keyword.get(opts, :test_stream, [])})
    end

    def run(prompt, opts) when is_binary(prompt) and is_list(opts) do
      send(self(), {:run_default, prompt, opts})
      Keyword.get(opts, :test_result, {:ok, Keyword.get(opts, :test_stream, [])})
    end

    def cancel(provider, session_id) when is_atom(provider) and is_binary(session_id) do
      send(self(), {:cancel, provider, session_id})
      :ok
    end
  end

  defmodule MissingHarness do
  end

  test "capabilities advertise stream and backend-owned model/provider selection" do
    capabilities = Harness.capabilities()

    assert capabilities.streaming? == true
    assert capabilities.provider_selection? == false
    assert capabilities.model_selection? == false
    assert is_boolean(capabilities.cancellation?)
  end

  test "start/2 runs with explicit harness provider and extracts final text from provider event variance" do
    request =
      request_fixture(%{
        options: %{
          test_stream: [
            %{
              "type" => "assistant",
              "provider" => "codex",
              "session_id" => "sess-1",
              "message" => %{
                "content" => [
                  %{"type" => "text", "text" => "Hello "},
                  %{"type" => "thinking", "thinking" => "pondering"}
                ]
              }
            },
            %{
              "type" => "result",
              "payload" => %{
                "output_text" => "Hello world",
                "finish_reason" => "stop",
                "usage" => %{"input_tokens" => 3, "output_tokens" => 4}
              }
            },
            %{"type" => "session_completed", "payload" => %{"status" => "ok"}}
          ]
        }
      })

    assert {:ok, %Result{} = result} =
             Harness.start(
               request,
               harness_module: TestHarness,
               harness_provider: :codex
             )

    assert_receive {:run_with_provider, :codex, prompt, opts}
    assert prompt =~ "System:"
    assert prompt =~ "User:"
    assert Keyword.has_key?(opts, :metadata)

    assert result.status == :completed
    assert result.text == "Hello world"
    assert result.provider == "codex"
    assert result.finish_reason == "stop"
    assert result.usage.input_tokens == 3
    assert result.usage.output_tokens == 4
    assert result.usage.total_tokens == 7
    assert result.metadata.session_id == "sess-1"
  end

  test "stream/3 emits started delta thinking completed events and normalized result" do
    request =
      request_fixture(%{
        options: %{
          test_stream: [
            %{type: :session_started, provider: :codex, session_id: "session-1", payload: %{}},
            %{type: :output_text_delta, payload: %{"text" => "chunk-1"}},
            %{"type" => "thinking_delta", "payload" => %{"text" => "thought-1"}},
            %{
              type: :session_completed,
              payload: %{
                "output_text" => "chunk-1 done",
                "usage" => %{"input_tokens" => 1, "output_tokens" => 2}
              }
            }
          ]
        }
      })

    assert {:ok, %Result{} = result} =
             Harness.stream(
               request,
               fn %Event{} = event -> send(self(), {:event, event}) end,
               harness_module: TestHarness,
               harness_provider: :codex
             )

    events =
      []
      |> collect_events()
      |> Enum.reverse()

    assert Enum.map(events, & &1.lifecycle) == [:started, :delta, :thinking, :completed]

    assert result.status == :completed
    assert result.text == "chunk-1 done"
    assert result.provider == :codex
    assert result.usage.input_tokens == 1
    assert result.usage.output_tokens == 2
    assert result.usage.total_tokens == 3
  end

  test "stream/3 emits failed lifecycle and returns normalized error on session failure events" do
    request =
      request_fixture(%{
        options: %{
          test_stream: [
            %{type: :session_started, provider: :codex, session_id: "session-1", payload: %{}},
            %{type: :session_failed, payload: %{"error" => "boom"}}
          ]
        }
      })

    assert {:error, %Error{} = error} =
             Harness.stream(
               request,
               fn %Event{} = event -> send(self(), {:event, event}) end,
               harness_module: TestHarness,
               harness_provider: :codex
             )

    assert error.category == :provider

    events =
      []
      |> collect_events()
      |> Enum.reverse()

    assert Enum.map(events, & &1.lifecycle) == [:started, :failed]
  end

  test "start/2 marks non-retryable provider status errors correctly" do
    request =
      request_fixture(%{
        options: %{
          test_result: {:error, %{status: 422, message: "invalid request"}}
        }
      })

    assert {:error, %Error{} = error} =
             Harness.start(
               request,
               harness_module: TestHarness,
               harness_provider: :codex
             )

    assert error.category == :provider
    assert error.retryable? == false
  end

  test "start/2 marks transient provider status errors as retryable" do
    request =
      request_fixture(%{
        options: %{
          test_result: {:error, %{"status" => "503", "message" => "upstream unavailable"}}
        }
      })

    assert {:error, %Error{} = error} =
             Harness.start(
               request,
               harness_module: TestHarness,
               harness_provider: :codex
             )

    assert error.category == :provider
    assert error.retryable? == true
  end

  test "stream/3 normalizes non-empty delta chunks emitted by harness events" do
    request =
      request_fixture(%{
        options: %{
          test_stream: [
            %{type: :session_started, provider: :codex, session_id: "session-1", payload: %{}},
            %{type: :output_text_delta, payload: %{"text" => "hello "}},
            %{type: :output_text_delta, payload: %{"text" => "world"}},
            %{type: :session_completed, payload: %{"output_text" => "hello world"}}
          ]
        }
      })

    assert {:ok, %Result{}} =
             Harness.stream(
               request,
               fn %Event{} = event -> send(self(), {:event, event}) end,
               harness_module: TestHarness,
               harness_provider: :codex
             )

    events =
      []
      |> collect_events()
      |> Enum.reverse()

    deltas = Enum.filter(events, &(&1.lifecycle == :delta))
    assert Enum.map(deltas, & &1.delta) == ["hello", "world"]
  end

  test "cancel/2 delegates to harness cancellation with provider and session_id" do
    assert :ok =
             Harness.cancel(
               %{provider: :codex, session_id: "session-1"},
               harness_module: TestHarness
             )

    assert_receive {:cancel, :codex, "session-1"}
  end

  test "cancel/2 returns config error when session_id is missing" do
    assert {:error, %Error{} = error} =
             Harness.cancel(
               %{provider: :codex},
               harness_module: TestHarness
             )

    assert error.category == :config
  end

  test "start/2 returns config error when harness module is missing required run function" do
    request = request_fixture()

    assert {:error, %Error{} = error} =
             Harness.start(
               request,
               harness_module: MissingHarness
             )

    assert error.category == :config
  end

  defp request_fixture(overrides \\ %{}) do
    base = %{
      request_id: "r1",
      conversation_id: "c1",
      backend: :harness,
      messages: [%{role: :user, content: "hello"}],
      system_prompt: "You are helpful.",
      stream?: true,
      metadata: %{trace_id: "trace-1"},
      options: %{}
    }

    base
    |> Map.merge(overrides)
    |> Request.new!()
  end

  defp collect_events(events) do
    receive do
      {:event, event} -> collect_events([event | events])
    after
      20 -> events
    end
  end
end
