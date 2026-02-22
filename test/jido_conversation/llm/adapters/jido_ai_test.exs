defmodule Jido.Conversation.LLM.Adapters.JidoAITest do
  use ExUnit.Case, async: true

  alias Jido.Conversation.LLM.Adapters.JidoAI
  alias Jido.Conversation.LLM.Error
  alias Jido.Conversation.LLM.Event
  alias Jido.Conversation.LLM.Request
  alias Jido.Conversation.LLM.Result

  defmodule TestJidoAI do
    def resolve_model(:fast), do: "openai:gpt-4o-mini"
    def resolve_model(:capable), do: "anthropic:claude-sonnet-4-20250514"
    def resolve_model(model) when is_binary(model), do: model
    def resolve_model(_), do: raise(ArgumentError, "unknown alias")
  end

  defmodule TestLLMClient do
    def generate_text(context, model, messages, opts) do
      send(context.test_pid, {:generate_text, model, messages, opts})
      context.generate_result
    end

    def stream_text(context, model, messages, opts) do
      send(context.test_pid, {:stream_text, model, messages, opts})
      context.stream_result
    end

    def process_stream(context, _stream_response, opts) do
      send(context.test_pid, {:process_stream, opts})

      on_result = Keyword.get(opts, :on_result)
      on_thinking = Keyword.get(opts, :on_thinking)

      Enum.each(Map.get(context, :content_chunks, []), fn chunk ->
        if is_function(on_result, 1), do: on_result.(chunk)
      end)

      Enum.each(Map.get(context, :thinking_chunks, []), fn chunk ->
        if is_function(on_thinking, 1), do: on_thinking.(chunk)
      end)

      context.process_result
    end
  end

  defmodule MissingLLMClient do
  end

  test "capabilities advertise streaming and provider/model selection" do
    assert JidoAI.capabilities() == %{
             streaming?: true,
             cancellation?: false,
             provider_selection?: true,
             model_selection?: true
           }
  end

  test "start/2 resolves provider:model and returns normalized result" do
    request =
      request_fixture(%{
        model: "claude-3-7-sonnet-latest",
        provider: "anthropic",
        max_tokens: 256,
        temperature: 0.2,
        timeout_ms: 12_000,
        options: %{tool_choice: :auto}
      })

    llm_context = %{
      test_pid: self(),
      generate_result:
        {:ok,
         %{
           model: "anthropic:claude-3-7-sonnet-latest",
           finish_reason: :stop,
           message: %{content: "hello from adapter"},
           usage: %{input_tokens: 11, output_tokens: 7}
         }}
    }

    assert {:ok, %Result{} = result} =
             JidoAI.start(
               request,
               llm_client_module: TestLLMClient,
               jido_ai_module: TestJidoAI,
               llm_client_context: llm_context
             )

    assert_receive {:generate_text, "anthropic:claude-3-7-sonnet-latest", messages, opts}
    assert List.first(messages).role == :system
    assert Keyword.get(opts, :max_tokens) == 256
    assert Keyword.get(opts, :temperature) == 0.2
    assert Keyword.get(opts, :receive_timeout) == 12_000
    assert Keyword.get(opts, :tool_choice) == :auto

    assert result.status == :completed
    assert result.text == "hello from adapter"
    assert result.provider == "anthropic"
    assert result.model == "anthropic:claude-3-7-sonnet-latest"
    assert result.finish_reason == :stop
    assert result.usage.input_tokens == 11
    assert result.usage.output_tokens == 7
    assert result.usage.total_tokens == 18
  end

  test "start/2 supports alias resolution and provider override" do
    request = request_fixture(%{model: :capable, provider: "openai"})

    llm_context = %{
      test_pid: self(),
      generate_result: {:ok, %{message: %{content: "ok"}}}
    }

    assert {:ok, %Result{} = result} =
             JidoAI.start(
               request,
               llm_client_module: TestLLMClient,
               jido_ai_module: TestJidoAI,
               llm_client_context: llm_context
             )

    assert_receive {:generate_text, "openai:claude-sonnet-4-20250514", _messages, _opts}
    assert result.provider == "openai"
  end

  test "start/2 normalizes provider auth errors" do
    request = request_fixture()

    llm_context = %{
      test_pid: self(),
      generate_result: {:error, %{status: 401, message: "unauthorized"}}
    }

    assert {:error, %Error{} = error} =
             JidoAI.start(
               request,
               llm_client_module: TestLLMClient,
               jido_ai_module: TestJidoAI,
               llm_client_context: llm_context
             )

    assert error.category == :auth
    assert error.retryable? == false
  end

  test "start/2 normalizes canceled reason errors" do
    request = request_fixture()

    llm_context = %{
      test_pid: self(),
      generate_result: {:error, %{reason: :canceled, message: "canceled"}}
    }

    assert {:error, %Error{} = error} =
             JidoAI.start(
               request,
               llm_client_module: TestLLMClient,
               jido_ai_module: TestJidoAI,
               llm_client_context: llm_context
             )

    assert error.category == :canceled
    assert error.retryable? == false
  end

  test "start/2 marks non-retryable provider status errors correctly" do
    request = request_fixture()

    llm_context = %{
      test_pid: self(),
      generate_result: {:error, %{status: 422, message: "invalid request"}}
    }

    assert {:error, %Error{} = error} =
             JidoAI.start(
               request,
               llm_client_module: TestLLMClient,
               jido_ai_module: TestJidoAI,
               llm_client_context: llm_context
             )

    assert error.category == :provider
    assert error.retryable? == false
  end

  test "start/2 marks transient provider status errors as retryable" do
    request = request_fixture()

    llm_context = %{
      test_pid: self(),
      generate_result: {:error, %{"status" => "503", "message" => "upstream unavailable"}}
    }

    assert {:error, %Error{} = error} =
             JidoAI.start(
               request,
               llm_client_module: TestLLMClient,
               jido_ai_module: TestJidoAI,
               llm_client_context: llm_context
             )

    assert error.category == :provider
    assert error.retryable? == true
  end

  test "stream/3 emits started delta thinking completed lifecycle events" do
    request = request_fixture(%{model: "anthropic:claude-sonnet-4"})

    llm_context = %{
      test_pid: self(),
      stream_result: {:ok, :stream_ref},
      content_chunks: ["chunk-1", "chunk-2"],
      thinking_chunks: ["thought-1"],
      process_result:
        {:ok,
         %{
           finish_reason: :stop,
           message: %{
             content: [
               %{type: :text, text: "chunk-1"},
               %{type: :text, text: "chunk-2"},
               %{type: :thinking, thinking: "thought-1"}
             ]
           },
           usage: %{"input_tokens" => 3, "output_tokens" => 5}
         }}
    }

    events = []

    assert {:ok, %Result{} = result} =
             JidoAI.stream(
               request,
               fn %Event{} = event -> send(self(), {:event, event}) end,
               llm_client_module: TestLLMClient,
               jido_ai_module: TestJidoAI,
               llm_client_context: llm_context
             )

    events =
      events
      |> collect_events()
      |> Enum.reverse()

    assert Enum.map(events, & &1.lifecycle) == [:started, :delta, :delta, :thinking, :completed]

    assert result.text == "chunk-1\nchunk-2"
    assert result.usage.input_tokens == 3
    assert result.usage.output_tokens == 5
    assert result.usage.total_tokens == 8
  end

  test "stream/3 emits failed lifecycle event on processing errors" do
    request = request_fixture(%{model: :fast})

    llm_context = %{
      test_pid: self(),
      stream_result: {:ok, :stream_ref},
      process_result: {:error, :timeout}
    }

    assert {:error, %Error{} = error} =
             JidoAI.stream(
               request,
               fn %Event{} = event -> send(self(), {:event, event}) end,
               llm_client_module: TestLLMClient,
               jido_ai_module: TestJidoAI,
               llm_client_context: llm_context
             )

    assert error.category == :timeout

    events =
      []
      |> collect_events()
      |> Enum.reverse()

    assert Enum.map(events, & &1.lifecycle) == [:started, :failed]
  end

  test "start/2 returns config error when llm client function is missing" do
    request = request_fixture()

    assert {:error, %Error{} = error} =
             JidoAI.start(
               request,
               llm_client_module: MissingLLMClient,
               jido_ai_module: TestJidoAI,
               llm_client_context: %{test_pid: self()}
             )

    assert error.category == :config
  end

  test "cancel/2 reports unsupported explicit cancellation for phase 3" do
    assert {:error, %Error{} = error} = JidoAI.cancel(:ref, [])
    assert error.category == :config
  end

  defp request_fixture(overrides \\ %{}) do
    base = %{
      request_id: "r1",
      conversation_id: "c1",
      backend: :jido_ai,
      messages: [%{role: :user, content: "hello"}],
      model: :fast,
      provider: nil,
      system_prompt: "You are helpful.",
      stream?: true,
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
