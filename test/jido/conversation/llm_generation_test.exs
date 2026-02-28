defmodule Jido.Conversation.LLMGenerationTest do
  use ExUnit.Case, async: true

  alias Jido.Conversation
  alias JidoConversation.LLM.Error, as: LLMError
  alias JidoConversation.LLM.Event, as: LLMEvent
  alias JidoConversation.LLM.Request, as: LLMRequest
  alias JidoConversation.LLM.Result, as: LLMResult

  defmodule StartBackendStub do
    @behaviour JidoConversation.LLM.Backend

    @impl true
    def capabilities do
      %{
        streaming?: false,
        cancellation?: false,
        provider_selection?: true,
        model_selection?: true
      }
    end

    @impl true
    def start(%LLMRequest{} = request, opts) do
      send(Keyword.get(opts, :test_pid, self()), {:start_backend_called, request, opts})

      {:ok,
       LLMResult.new!(%{
         request_id: request.request_id,
         conversation_id: request.conversation_id,
         backend: request.backend,
         status: :completed,
         text: "assistant from start",
         provider: request.provider || "anthropic",
         model: request.model || "claude-test",
         finish_reason: :stop,
         usage: %{input_tokens: 4, output_tokens: 6}
       })}
    end

    @impl true
    def stream(%LLMRequest{} = request, _emit, _opts) do
      start(request, [])
    end

    @impl true
    def cancel(_execution_ref, _opts), do: :ok
  end

  defmodule StreamBackendStub do
    @behaviour JidoConversation.LLM.Backend

    @impl true
    def capabilities do
      %{
        streaming?: true,
        cancellation?: false,
        provider_selection?: true,
        model_selection?: true
      }
    end

    @impl true
    def start(%LLMRequest{} = request, _opts) do
      {:ok,
       LLMResult.new!(%{
         request_id: request.request_id,
         conversation_id: request.conversation_id,
         backend: request.backend,
         status: :completed,
         text: "assistant from stream",
         provider: request.provider || "anthropic",
         model: request.model || "claude-test"
       })}
    end

    @impl true
    def stream(%LLMRequest{} = request, emit, opts) do
      send(Keyword.get(opts, :test_pid, self()), {:stream_backend_called, request, opts})

      _ =
        emit.(
          LLMEvent.new!(%{
            request_id: request.request_id,
            conversation_id: request.conversation_id,
            backend: request.backend,
            lifecycle: :delta,
            delta: "stream-delta"
          })
        )

      {:ok,
       LLMResult.new!(%{
         request_id: request.request_id,
         conversation_id: request.conversation_id,
         backend: request.backend,
         status: :completed,
         text: "assistant from stream",
         provider: request.provider || "anthropic",
         model: request.model || "claude-test"
       })}
    end

    @impl true
    def cancel(_execution_ref, _opts), do: :ok
  end

  defmodule ErrorBackendStub do
    @behaviour JidoConversation.LLM.Backend

    @impl true
    def capabilities do
      %{
        streaming?: false,
        cancellation?: false,
        provider_selection?: true,
        model_selection?: true
      }
    end

    @impl true
    def start(%LLMRequest{} = _request, _opts) do
      {:error,
       LLMError.new!(category: :provider, message: "upstream unavailable", retryable?: true)}
    end

    @impl true
    def stream(%LLMRequest{} = request, _emit, opts), do: start(request, opts)

    @impl true
    def cancel(_execution_ref, _opts), do: :ok
  end

  test "generate_assistant_reply/2 executes backend and records assistant text" do
    conversation = Conversation.new(conversation_id: "conv-generate-start")
    {:ok, conversation, _} = Conversation.send_user_message(conversation, "hello model")

    assert {:ok, conversation, %LLMResult{} = result} =
             Conversation.generate_assistant_reply(conversation,
               llm: %{backend: :stub_start},
               llm_config: llm_config(:stub_start, StartBackendStub, stream?: false),
               backend_opts: [test_pid: self()]
             )

    assert_receive {:start_backend_called, %LLMRequest{} = request, backend_opts}
    assert backend_opts[:test_pid] == self()
    assert request.messages == [%{role: :user, content: "hello model"}]

    derived = Conversation.derived_state(conversation)

    assert Enum.map(derived.messages, & &1.role) == [:user, :assistant]
    assert Enum.map(derived.messages, & &1.content) == ["hello model", "assistant from start"]

    [_, assistant_message] = derived.messages
    assert assistant_message.metadata.backend == "stub_start"
    assert assistant_message.metadata.provider == "anthropic"

    assert result.text == "assistant from start"
  end

  test "generate_assistant_reply/2 supports streaming callbacks" do
    conversation = Conversation.new(conversation_id: "conv-generate-stream")
    {:ok, conversation, _} = Conversation.send_user_message(conversation, "stream this")

    assert {:ok, conversation, %LLMResult{} = result} =
             Conversation.generate_assistant_reply(conversation,
               llm: %{backend: :stub_stream},
               llm_config: llm_config(:stub_stream, StreamBackendStub, stream?: true),
               stream?: true,
               backend_opts: [test_pid: self()],
               on_event: fn event -> send(self(), {:llm_event, event.lifecycle}) end
             )

    assert_receive {:stream_backend_called, %LLMRequest{}, _opts}
    assert_receive {:llm_event, :delta}

    derived = Conversation.derived_state(conversation)
    assert Enum.map(derived.messages, & &1.content) == ["stream this", "assistant from stream"]
    assert result.text == "assistant from stream"
  end

  test "generate_assistant_reply/2 returns backend errors without recording assistant text" do
    conversation = Conversation.new(conversation_id: "conv-generate-error")
    {:ok, conversation, _} = Conversation.send_user_message(conversation, "fail please")

    assert {:error, %LLMError{} = error} =
             Conversation.generate_assistant_reply(conversation,
               llm: %{backend: :stub_error},
               llm_config: llm_config(:stub_error, ErrorBackendStub, stream?: false)
             )

    assert error.category == :provider

    derived = Conversation.derived_state(conversation)
    assert Enum.map(derived.messages, & &1.content) == ["fail please"]
  end

  defp llm_config(backend, backend_module, opts) do
    [
      default_backend: backend,
      default_stream?: Keyword.get(opts, :stream?, false),
      default_timeout_ms: 30_000,
      default_provider: "anthropic",
      default_model: "claude-test",
      backends: [
        {backend,
         [
           module: backend_module,
           stream?: Keyword.get(opts, :stream?, false),
           timeout_ms: 30_000,
           provider: "anthropic",
           model: "claude-test",
           options: []
         ]}
      ]
    ]
  end
end
