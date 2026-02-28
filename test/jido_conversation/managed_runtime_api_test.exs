defmodule JidoConversation.ManagedRuntimeApiTest do
  use ExUnit.Case, async: false

  alias Jido.Conversation
  alias JidoConversation
  alias JidoConversation.LLM.Backend
  alias JidoConversation.LLM.Request, as: LLMRequest
  alias JidoConversation.LLM.Result, as: LLMResult

  defmodule FacadeFastBackendStub do
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
      send(
        Keyword.get(opts, :test_pid, self()),
        {:facade_fast_backend_called, request.request_id}
      )

      {:ok,
       LLMResult.new!(%{
         request_id: request.request_id,
         conversation_id: request.conversation_id,
         backend: request.backend,
         status: :completed,
         text: "facade fast reply",
         provider: request.provider || "anthropic",
         model: request.model || "claude-test"
       })}
    end

    @impl true
    def stream(%LLMRequest{} = request, _emit, opts), do: start(request, opts)

    @impl true
    def cancel(_execution_ref, _opts), do: :ok
  end

  defmodule FacadeSlowBackendStub do
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
      send(
        Keyword.get(opts, :test_pid, self()),
        {:facade_slow_backend_started, request.request_id}
      )

      Process.sleep(Keyword.get(opts, :sleep_ms, 1_000))

      {:ok,
       LLMResult.new!(%{
         request_id: request.request_id,
         conversation_id: request.conversation_id,
         backend: request.backend,
         status: :completed,
         text: "facade slow reply",
         provider: request.provider || "anthropic",
         model: request.model || "claude-test"
       })}
    end

    @impl true
    def stream(%LLMRequest{} = request, _emit, opts), do: start(request, opts)

    @impl true
    def cancel(_execution_ref, _opts), do: :ok
  end

  test "managed facade supports start, read, and stop" do
    assert {:ok, pid, :started} =
             JidoConversation.ensure_conversation(conversation_id: "facade-conv-1")

    assert pid == JidoConversation.whereis_conversation("facade-conv-1")

    assert {:ok, _conversation, _directives} =
             JidoConversation.send_user_message("facade-conv-1", "hello facade")

    assert {:ok, derived} = JidoConversation.derived_state("facade-conv-1")
    assert derived.last_user_message == "hello facade"

    assert {:ok, timeline} = JidoConversation.conversation_timeline("facade-conv-1")

    assert Enum.any?(
             timeline,
             &(&1.kind == :message and &1.role == :user and &1.content == "hello facade")
           )

    assert :ok = JidoConversation.stop_conversation("facade-conv-1")
    assert JidoConversation.whereis_conversation("facade-conv-1") == nil
  end

  test "managed facade supports project-scoped locators" do
    locator = {"facade-project", "shared-conv"}

    assert {:ok, _conversation, _directives} =
             JidoConversation.send_user_message(locator, "from project scope")

    assert {:ok, derived} = JidoConversation.derived_state(locator)
    assert derived.last_user_message == "from project scope"

    assert {:ok, conversation} = JidoConversation.conversation(locator)
    assert conversation.state.metadata.project_id == "facade-project"

    assert :ok = JidoConversation.stop_conversation(locator)
  end

  test "managed facade supports generation and cancellation" do
    conversation_id = "facade-conv-generate"

    assert {:ok, _conversation, _directives} =
             JidoConversation.send_user_message(conversation_id, "hello model")

    assert {:ok, generation_ref} =
             JidoConversation.generate_assistant_reply(conversation_id,
               llm: %{backend: :facade_fast_stub},
               llm_config: llm_config(:facade_fast_stub, FacadeFastBackendStub),
               backend_opts: [test_pid: self()]
             )

    assert_receive {:facade_fast_backend_called, _request_id}

    assert_receive {:jido_conversation,
                    {:generation_result, ^generation_ref, {:ok, %LLMResult{} = result}}}

    assert result.text == "facade fast reply"

    assert {:ok, derived} = JidoConversation.derived_state(conversation_id)
    assert Enum.map(derived.messages, & &1.content) == ["hello model", "facade fast reply"]

    assert :ok = JidoConversation.stop_conversation(conversation_id)
  end

  test "managed facade supports cancel API" do
    conversation_id = "facade-conv-cancel"

    assert {:ok, _conversation, _directives} =
             JidoConversation.send_user_message(conversation_id, "please wait")

    assert {:ok, generation_ref} =
             JidoConversation.generate_assistant_reply(conversation_id,
               llm: %{backend: :facade_slow_stub},
               llm_config: llm_config(:facade_slow_stub, FacadeSlowBackendStub),
               backend_opts: [test_pid: self(), sleep_ms: 2_000]
             )

    assert_receive {:facade_slow_backend_started, _request_id}

    assert :ok = JidoConversation.cancel_generation(conversation_id, "facade_cancel")
    assert_receive {:jido_conversation, {:generation_canceled, ^generation_ref, "facade_cancel"}}

    refute_receive {:jido_conversation, {:generation_result, ^generation_ref, _}}, 150

    assert {:ok, derived} = JidoConversation.derived_state(conversation_id)
    assert derived.status == :canceled
    assert derived.cancel_reason == "facade_cancel"

    assert :ok = JidoConversation.stop_conversation(conversation_id)
  end

  test "send_and_generate/3 runs a full managed turn" do
    conversation_id = "facade-conv-turn"

    assert {:ok, conversation, %LLMResult{} = result} =
             JidoConversation.send_and_generate(conversation_id, "hello turn",
               generation_opts: [
                 llm: %{backend: :facade_fast_stub},
                 llm_config: llm_config(:facade_fast_stub, FacadeFastBackendStub),
                 backend_opts: [test_pid: self()]
               ],
               await_opts: [timeout_ms: 1_000]
             )

    assert_receive {:facade_fast_backend_called, _request_id}
    assert result.text == "facade fast reply"

    assert Enum.map(Conversation.derived_state(conversation).messages, & &1.content) == [
             "hello turn",
             "facade fast reply"
           ]

    assert :ok = JidoConversation.stop_conversation(conversation_id)
  end

  test "await_generation/3 timeout cancels by default" do
    conversation_id = "facade-conv-await-timeout"

    assert {:ok, _conversation, _directives} =
             JidoConversation.send_user_message(conversation_id, "please wait")

    assert {:ok, generation_ref} =
             JidoConversation.generate_assistant_reply(conversation_id,
               llm: %{backend: :facade_slow_stub},
               llm_config: llm_config(:facade_slow_stub, FacadeSlowBackendStub),
               backend_opts: [test_pid: self(), sleep_ms: 2_000]
             )

    assert_receive {:facade_slow_backend_started, _request_id}

    assert {:error, :timeout} =
             JidoConversation.await_generation(conversation_id, generation_ref, timeout_ms: 10)

    assert_receive {:jido_conversation, {:generation_canceled, ^generation_ref, "await_timeout"}}

    assert {:ok, derived} = JidoConversation.derived_state(conversation_id)
    assert derived.status == :canceled
    assert derived.cancel_reason == "await_timeout"

    assert :ok = JidoConversation.stop_conversation(conversation_id)
  end

  test "await_generation/3 timeout can leave generation running" do
    conversation_id = "facade-conv-await-timeout-no-cancel"

    assert {:ok, _conversation, _directives} =
             JidoConversation.send_user_message(conversation_id, "please wait")

    assert {:ok, generation_ref} =
             JidoConversation.generate_assistant_reply(conversation_id,
               llm: %{backend: :facade_slow_stub},
               llm_config: llm_config(:facade_slow_stub, FacadeSlowBackendStub),
               backend_opts: [test_pid: self(), sleep_ms: 150]
             )

    assert_receive {:facade_slow_backend_started, _request_id}

    assert {:error, :timeout} =
             JidoConversation.await_generation(conversation_id, generation_ref,
               timeout_ms: 10,
               cancel_on_timeout?: false
             )

    assert_receive {:jido_conversation,
                    {:generation_result, ^generation_ref, {:ok, %LLMResult{} = result}}},
                   1_000

    assert result.text == "facade slow reply"

    assert {:ok, derived} = JidoConversation.derived_state(conversation_id)
    assert Enum.map(derived.messages, & &1.content) == ["please wait", "facade slow reply"]

    assert :ok = JidoConversation.stop_conversation(conversation_id)
  end

  test "managed facade validates locators" do
    assert {:error, :invalid_locator} = JidoConversation.conversation("")
    assert {:error, :invalid_locator} = JidoConversation.cancel_generation({"project", ""})
    assert {:error, :not_found} = JidoConversation.conversation("missing-facade-conv")
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
