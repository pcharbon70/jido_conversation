defmodule Jido.Conversation.ServerTest do
  use ExUnit.Case, async: true

  alias Jido.Conversation
  alias Jido.Conversation.Server
  alias JidoConversation.LLM.Backend
  alias JidoConversation.LLM.Error, as: LLMError
  alias JidoConversation.LLM.Request, as: LLMRequest
  alias JidoConversation.LLM.Result, as: LLMResult

  defmodule FastBackendStub do
    @behaviour Backend

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
      send(Keyword.get(opts, :test_pid, self()), {:fast_backend_called, request.request_id})

      {:ok,
       LLMResult.new!(%{
         request_id: request.request_id,
         conversation_id: request.conversation_id,
         backend: request.backend,
         status: :completed,
         text: "server fast reply",
         provider: request.provider || "anthropic",
         model: request.model || "claude-test"
       })}
    end

    @impl true
    def stream(%LLMRequest{} = request, _emit, opts), do: start(request, opts)

    @impl true
    def cancel(_execution_ref, _opts), do: :ok
  end

  defmodule SlowBackendStub do
    @behaviour Backend

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
      sleep_ms = Keyword.get(opts, :sleep_ms, 1_000)
      send(Keyword.get(opts, :test_pid, self()), {:slow_backend_started, request.request_id})
      Process.sleep(sleep_ms)

      {:ok,
       LLMResult.new!(%{
         request_id: request.request_id,
         conversation_id: request.conversation_id,
         backend: request.backend,
         status: :completed,
         text: "server slow reply",
         provider: request.provider || "anthropic",
         model: request.model || "claude-test"
       })}
    end

    @impl true
    def stream(%LLMRequest{} = request, _emit, opts), do: start(request, opts)

    @impl true
    def cancel(_execution_ref, _opts), do: :ok
  end

  defmodule ErrorBackendStub do
    @behaviour Backend

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
       LLMError.new!(category: :provider, message: "server backend failed", retryable?: true)}
    end

    @impl true
    def stream(%LLMRequest{} = request, _emit, opts), do: start(request, opts)

    @impl true
    def cancel(_execution_ref, _opts), do: :ok
  end

  test "generate_assistant_reply/2 runs asynchronously and updates conversation state" do
    {:ok, server} = Server.start_link(conversation_id: "server-conv-1")

    assert {:ok, _conversation, _directives} =
             Server.send_user_message(server, "hello from server")

    assert {:ok, generation_ref} =
             Server.generate_assistant_reply(server,
               llm: %{backend: :fast_stub},
               llm_config: llm_config(:fast_stub, FastBackendStub),
               backend_opts: [test_pid: self()]
             )

    assert_receive {:fast_backend_called, _request_id}

    assert_receive {:jido_conversation,
                    {:generation_result, ^generation_ref, {:ok, %LLMResult{} = result}}}

    assert result.text == "server fast reply"

    conversation = Server.conversation(server)
    derived = Conversation.derived_state(conversation)

    assert Enum.map(derived.messages, & &1.content) == ["hello from server", "server fast reply"]
    assert derived.status == :responding
  end

  test "generation in progress blocks new writes and can be canceled" do
    {:ok, server} = Server.start_link(conversation_id: "server-conv-2")

    assert {:ok, _conversation, _directives} = Server.send_user_message(server, "please wait")

    assert {:ok, generation_ref} =
             Server.generate_assistant_reply(server,
               llm: %{backend: :slow_stub},
               llm_config: llm_config(:slow_stub, SlowBackendStub),
               backend_opts: [test_pid: self(), sleep_ms: 2_000]
             )

    assert_receive {:slow_backend_started, _request_id}

    assert {:error, :generation_in_progress} =
             Server.send_user_message(server, "new input while running")

    assert {:error, :generation_in_progress} =
             Server.record_assistant_message(server, "assistant while running")

    assert {:error, :generation_in_progress} =
             Server.configure_llm(server, :jido_ai, provider: "anthropic")

    assert {:error, :generation_in_progress} =
             Server.configure_skills(server, ["web_search"])

    assert {:error, :generation_in_progress} =
             Server.generate_assistant_reply(server, llm: %{backend: :slow_stub})

    assert :ok = Server.cancel_generation(server, "user_cancel")

    assert_receive {:jido_conversation, {:generation_canceled, ^generation_ref, "user_cancel"}}

    refute_receive {:jido_conversation, {:generation_result, ^generation_ref, _result}}, 150

    conversation = Server.conversation(server)
    derived = Conversation.derived_state(conversation)

    assert Enum.map(derived.messages, & &1.content) == ["please wait"]
    assert derived.status == :canceled
    assert derived.cancel_reason == "user_cancel"
  end

  test "configure_skills/2 updates derived state" do
    {:ok, server} = Server.start_link(conversation_id: "server-conv-skills")

    assert {:ok, _conversation, _directives} =
             Server.configure_skills(server, ["web_search", :code_exec, "web_search"])

    conversation = Server.conversation(server)
    derived = Conversation.derived_state(conversation)

    assert derived.skills.enabled == ["web_search", "code_exec"]
  end

  test "record_assistant_message/3 updates derived state" do
    {:ok, server} = Server.start_link(conversation_id: "server-conv-assistant")

    assert {:ok, _conversation, _directives} =
             Server.send_user_message(server, "hello there")

    assert {:ok, _conversation, _directives} =
             Server.record_assistant_message(server, "hi from managed")

    conversation = Server.conversation(server)
    derived = Conversation.derived_state(conversation)

    assert Enum.map(derived.messages, & &1.content) == ["hello there", "hi from managed"]
    assert derived.status == :responding
  end

  test "llm_context/2 returns in-memory conversation context" do
    {:ok, server} = Server.start_link(conversation_id: "server-conv-context")

    assert {:ok, _conversation, _directives} =
             Server.send_user_message(server, "context hello")

    assert {:ok, _conversation, _directives} =
             Server.record_assistant_message(server, "context reply")

    assert [
             %{role: :user, content: "context hello"},
             %{role: :assistant, content: "context reply"}
           ] =
             Enum.map(Server.llm_context(server), fn message ->
               %{role: message.role, content: message.content}
             end)

    assert [
             %{role: :assistant, content: "context reply"}
           ] =
             Enum.map(Server.llm_context(server, max_messages: 1), fn message ->
               %{role: message.role, content: message.content}
             end)
  end

  test "thread/1 returns in-memory append-only journal struct" do
    {:ok, server} = Server.start_link(conversation_id: "server-conv-thread-struct")

    assert {:ok, _conversation, _directives} =
             Server.send_user_message(server, "thread struct hello")

    assert {:ok, _conversation, _directives} =
             Server.record_assistant_message(server, "thread struct reply")

    assert %Jido.Thread{id: "conv_thread_server-conv-thread-struct"} =
             thread =
             Server.thread(server)

    message_payloads =
      thread
      |> Jido.Thread.to_list()
      |> Enum.filter(&(&1.kind == :message))
      |> Enum.map(& &1.payload)

    assert message_payloads == [
             %{content: "thread struct hello", metadata: %{}, role: "user"},
             %{content: "thread struct reply", metadata: %{}, role: "assistant"}
           ]
  end

  test "thread_entries/1 returns in-memory append-only journal entries" do
    {:ok, server} = Server.start_link(conversation_id: "server-conv-thread")

    assert {:ok, _conversation, _directives} =
             Server.send_user_message(server, "thread hello")

    assert {:ok, _conversation, _directives} =
             Server.record_assistant_message(server, "thread reply")

    message_payloads =
      server
      |> Server.thread_entries()
      |> Enum.filter(&(&1.kind == :message))
      |> Enum.map(& &1.payload)

    assert message_payloads == [
             %{content: "thread hello", metadata: %{}, role: "user"},
             %{content: "thread reply", metadata: %{}, role: "assistant"}
           ]
  end

  test "generation errors are reported without mutating assistant messages" do
    {:ok, server} = Server.start_link(conversation_id: "server-conv-3")

    assert {:ok, _conversation, _directives} = Server.send_user_message(server, "fail server")

    assert {:ok, generation_ref} =
             Server.generate_assistant_reply(server,
               llm: %{backend: :error_stub},
               llm_config: llm_config(:error_stub, ErrorBackendStub)
             )

    assert_receive {:jido_conversation,
                    {:generation_result, ^generation_ref, {:error, %LLMError{} = error}}}

    assert error.category == :provider

    conversation = Server.conversation(server)
    derived = Conversation.derived_state(conversation)

    assert Enum.map(derived.messages, & &1.content) == ["fail server"]
    assert derived.status == :pending_llm
  end

  test "cancel_generation/2 returns error when no generation is active" do
    {:ok, server} = Server.start_link(conversation_id: "server-conv-4")

    assert {:error, :no_generation_in_progress} = Server.cancel_generation(server)
  end

  defp llm_config(backend, backend_module) do
    [
      default_backend: backend,
      default_stream?: false,
      default_timeout_ms: 30_000,
      default_provider: "anthropic",
      default_model: "claude-test",
      backends: [
        {backend,
         [
           module: backend_module,
           stream?: false,
           timeout_ms: 30_000,
           provider: "anthropic",
           model: "claude-test",
           options: []
         ]}
      ]
    ]
  end
end
