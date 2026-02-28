defmodule JidoConversation.ManagedRuntimeApiTest do
  use ExUnit.Case, async: false

  alias Jido.Conversation
  alias JidoConversation
  alias JidoConversation.LLM.Backend
  alias JidoConversation.LLM.Error, as: LLMError
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

  defmodule FacadeErrorBackendStub do
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
        {:facade_error_backend_called, request.request_id}
      )

      {:error,
       LLMError.new!(category: :provider, message: "facade backend failed", retryable?: true)}
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

  test "managed facade configures llm" do
    conversation_id = "facade-conv-llm"

    assert {:ok, _conversation, _directives} =
             JidoConversation.configure_llm(conversation_id, :jido_ai,
               provider: "anthropic",
               model: "claude-test",
               options: %{temperature: 0.2}
             )

    assert {:ok, derived} = JidoConversation.derived_state(conversation_id)

    assert derived.llm == %{
             backend: :jido_ai,
             provider: "anthropic",
             model: "claude-test",
             options: %{temperature: 0.2}
           }

    assert :ok = JidoConversation.stop_conversation(conversation_id)
  end

  test "managed facade configures skills" do
    conversation_id = "facade-conv-skills"

    assert {:ok, _conversation, _directives} =
             JidoConversation.configure_skills(conversation_id, [
               "web_search",
               :code_exec,
               "web_search"
             ])

    assert {:ok, derived} = JidoConversation.derived_state(conversation_id)
    assert derived.skills.enabled == ["web_search", "code_exec"]

    assert :ok = JidoConversation.stop_conversation(conversation_id)
  end

  test "managed facade records assistant messages" do
    conversation_id = "facade-conv-assistant"

    assert {:ok, _conversation, _directives} =
             JidoConversation.send_user_message(conversation_id, "hello from facade")

    assert {:ok, _conversation, _directives} =
             JidoConversation.record_assistant_message(conversation_id, "facade assistant reply")

    assert {:ok, derived} = JidoConversation.derived_state(conversation_id)

    assert Enum.map(derived.messages, & &1.content) == [
             "hello from facade",
             "facade assistant reply"
           ]

    assert :ok = JidoConversation.stop_conversation(conversation_id)
  end

  test "managed facade exposes in-memory conversation llm context" do
    conversation_id = "facade-conv-context"

    assert {:ok, _conversation, _directives} =
             JidoConversation.send_user_message(conversation_id, "facade context hello")

    assert {:ok, _conversation, _directives} =
             JidoConversation.record_assistant_message(conversation_id, "facade context reply")

    assert {:ok, context} = JidoConversation.conversation_llm_context(conversation_id)

    assert Enum.map(context, &{&1.role, &1.content}) == [
             {:user, "facade context hello"},
             {:assistant, "facade context reply"}
           ]

    assert {:ok, limited} =
             JidoConversation.conversation_llm_context(conversation_id, max_messages: 1)

    assert Enum.map(limited, &{&1.role, &1.content}) == [{:assistant, "facade context reply"}]

    assert :ok = JidoConversation.stop_conversation(conversation_id)
  end

  test "managed facade exposes in-memory conversation messages" do
    conversation_id = "facade-conv-messages"

    assert {:ok, _conversation, _directives} =
             JidoConversation.send_user_message(conversation_id, "facade messages hello")

    assert {:ok, _conversation, _directives} =
             JidoConversation.record_assistant_message(conversation_id, "facade messages reply")

    assert {:ok, messages} = JidoConversation.conversation_messages(conversation_id)

    assert Enum.map(messages, &{&1.role, &1.content}) == [
             {:user, "facade messages hello"},
             {:assistant, "facade messages reply"}
           ]

    assert {:ok, limited} =
             JidoConversation.conversation_messages(conversation_id, max_messages: 1)

    assert Enum.map(limited, &{&1.role, &1.content}) == [{:assistant, "facade messages reply"}]

    assert {:ok, user_only} =
             JidoConversation.conversation_messages(conversation_id, roles: [:user])

    assert Enum.map(user_only, &{&1.role, &1.content}) == [{:user, "facade messages hello"}]

    assert {:ok, assistant_only} =
             JidoConversation.conversation_messages(conversation_id, roles: ["assistant"])

    assert Enum.map(assistant_only, &{&1.role, &1.content}) == [
             {:assistant, "facade messages reply"}
           ]

    assert :ok = JidoConversation.stop_conversation(conversation_id)
  end

  test "managed facade exposes in-memory conversation thread struct" do
    conversation_id = "facade-conv-thread-struct"

    assert {:ok, _conversation, _directives} =
             JidoConversation.send_user_message(conversation_id, "facade thread struct hello")

    assert {:ok, _conversation, _directives} =
             JidoConversation.record_assistant_message(
               conversation_id,
               "facade thread struct reply"
             )

    assert {:ok, %Jido.Thread{id: "conv_thread_facade-conv-thread-struct"} = thread} =
             JidoConversation.conversation_thread(conversation_id)

    message_payloads =
      thread
      |> Jido.Thread.to_list()
      |> Enum.filter(&(&1.kind == :message))
      |> Enum.map(& &1.payload)

    assert message_payloads == [
             %{content: "facade thread struct hello", metadata: %{}, role: "user"},
             %{content: "facade thread struct reply", metadata: %{}, role: "assistant"}
           ]

    assert :ok = JidoConversation.stop_conversation(conversation_id)
  end

  test "managed facade exposes in-memory conversation thread entries" do
    conversation_id = "facade-conv-thread"

    assert {:ok, _conversation, _directives} =
             JidoConversation.send_user_message(conversation_id, "facade thread hello")

    assert {:ok, _conversation, _directives} =
             JidoConversation.record_assistant_message(conversation_id, "facade thread reply")

    assert {:ok, entries} = JidoConversation.conversation_thread_entries(conversation_id)

    message_payloads =
      entries
      |> Enum.filter(&(&1.kind == :message))
      |> Enum.map(& &1.payload)

    assert message_payloads == [
             %{content: "facade thread hello", metadata: %{}, role: "user"},
             %{content: "facade thread reply", metadata: %{}, role: "assistant"}
           ]

    assert :ok = JidoConversation.stop_conversation(conversation_id)
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

  test "managed facade enforces generation_in_progress for concurrent mutating commands" do
    conversation_id = "facade-conv-concurrency-guards"

    assert {:ok, _conversation, _directives} =
             JidoConversation.send_user_message(conversation_id, "please wait")

    assert {:ok, generation_ref} =
             JidoConversation.generate_assistant_reply(conversation_id,
               llm: %{backend: :facade_slow_stub},
               llm_config: llm_config(:facade_slow_stub, FacadeSlowBackendStub),
               backend_opts: [test_pid: self(), sleep_ms: 2_000]
             )

    assert_receive {:facade_slow_backend_started, _request_id}

    assert {:error, :generation_in_progress} =
             JidoConversation.send_user_message(conversation_id, "blocked")

    assert {:error, :generation_in_progress} =
             JidoConversation.record_assistant_message(conversation_id, "blocked")

    assert {:error, :generation_in_progress} =
             JidoConversation.configure_llm(conversation_id, :jido_ai,
               provider: "anthropic",
               model: "claude-test"
             )

    assert {:error, :generation_in_progress} =
             JidoConversation.configure_skills(conversation_id, ["web_search"])

    assert {:error, :generation_in_progress} =
             JidoConversation.generate_assistant_reply(conversation_id,
               llm: %{backend: :facade_slow_stub},
               llm_config: llm_config(:facade_slow_stub, FacadeSlowBackendStub),
               backend_opts: [test_pid: self(), sleep_ms: 2_000]
             )

    assert :ok = JidoConversation.cancel_generation(conversation_id, "concurrency_guard_cancel")

    assert_receive {:jido_conversation,
                    {:generation_canceled, ^generation_ref, "concurrency_guard_cancel"}}

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

  test "await_generation/3 returns backend errors" do
    conversation_id = "facade-conv-await-error"

    assert {:ok, _conversation, _directives} =
             JidoConversation.send_user_message(conversation_id, "return error")

    assert {:ok, generation_ref} =
             JidoConversation.generate_assistant_reply(conversation_id,
               llm: %{backend: :facade_error_stub},
               llm_config: llm_config(:facade_error_stub, FacadeErrorBackendStub),
               backend_opts: [test_pid: self()]
             )

    assert_receive {:facade_error_backend_called, _request_id}

    assert {:error, %LLMError{} = error} =
             JidoConversation.await_generation(conversation_id, generation_ref, timeout_ms: 1_000)

    assert error.category == :provider

    assert {:ok, derived} = JidoConversation.derived_state(conversation_id)
    assert Enum.map(derived.messages, & &1.content) == ["return error"]
    assert derived.status == :pending_llm

    assert :ok = JidoConversation.stop_conversation(conversation_id)
  end

  test "await_generation/3 returns canceled tuples when cancellation was requested" do
    conversation_id = "facade-conv-await-canceled"

    assert {:ok, _conversation, _directives} =
             JidoConversation.send_user_message(conversation_id, "cancel this run")

    assert {:ok, generation_ref} =
             JidoConversation.generate_assistant_reply(conversation_id,
               llm: %{backend: :facade_slow_stub},
               llm_config: llm_config(:facade_slow_stub, FacadeSlowBackendStub),
               backend_opts: [test_pid: self(), sleep_ms: 2_000]
             )

    assert_receive {:facade_slow_backend_started, _request_id}
    assert :ok = JidoConversation.cancel_generation(conversation_id, "manual_cancel")

    assert {:error, {:canceled, "manual_cancel"}} =
             JidoConversation.await_generation(conversation_id, generation_ref, timeout_ms: 1_000)

    assert {:ok, derived} = JidoConversation.derived_state(conversation_id)
    assert derived.status == :canceled
    assert derived.cancel_reason == "manual_cancel"

    assert :ok = JidoConversation.stop_conversation(conversation_id)
  end

  test "send_and_generate/3 propagates backend errors and keeps assistant history unchanged" do
    conversation_id = "facade-conv-turn-error"

    assert {:error, %LLMError{} = error} =
             JidoConversation.send_and_generate(conversation_id, "error turn",
               generation_opts: [
                 llm: %{backend: :facade_error_stub},
                 llm_config: llm_config(:facade_error_stub, FacadeErrorBackendStub),
                 backend_opts: [test_pid: self()]
               ],
               await_opts: [timeout_ms: 1_000]
             )

    assert error.category == :provider
    assert_receive {:facade_error_backend_called, _request_id}

    assert {:ok, derived} = JidoConversation.derived_state(conversation_id)
    assert Enum.map(derived.messages, & &1.content) == ["error turn"]
    assert derived.status == :pending_llm

    assert :ok = JidoConversation.stop_conversation(conversation_id)
  end

  test "managed facade validates locators" do
    assert {:error, :invalid_locator} = JidoConversation.conversation("")
    assert {:error, :invalid_locator} = JidoConversation.conversation_messages("")
    assert {:error, :invalid_locator} = JidoConversation.conversation_thread("")
    assert {:error, :invalid_locator} = JidoConversation.conversation_thread_entries("")
    assert {:error, :invalid_locator} = JidoConversation.conversation_llm_context("")
    assert {:error, :invalid_locator} = JidoConversation.configure_llm("", :jido_ai)
    assert {:error, :invalid_locator} = JidoConversation.record_assistant_message("", "bad")
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
