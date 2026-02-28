defmodule Jido.Conversation.RuntimeTest do
  use ExUnit.Case, async: false

  alias Jido.Conversation
  alias Jido.Conversation.Runtime
  alias JidoConversation.LLM.Backend
  alias JidoConversation.LLM.Request, as: LLMRequest
  alias JidoConversation.LLM.Result, as: LLMResult

  defmodule FastRuntimeBackendStub do
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
        {:runtime_fast_backend_called, request.request_id}
      )

      {:ok,
       LLMResult.new!(%{
         request_id: request.request_id,
         conversation_id: request.conversation_id,
         backend: request.backend,
         status: :completed,
         text: "runtime fast reply",
         provider: request.provider || "anthropic",
         model: request.model || "claude-test"
       })}
    end

    @impl true
    def stream(%LLMRequest{} = request, _emit, opts), do: start(request, opts)

    @impl true
    def cancel(_execution_ref, _opts), do: :ok
  end

  defmodule SlowRuntimeBackendStub do
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
        {:runtime_slow_backend_started, request.request_id}
      )

      Process.sleep(Keyword.get(opts, :sleep_ms, 1_000))

      {:ok,
       LLMResult.new!(%{
         request_id: request.request_id,
         conversation_id: request.conversation_id,
         backend: request.backend,
         status: :completed,
         text: "runtime slow reply",
         provider: request.provider || "anthropic",
         model: request.model || "claude-test"
       })}
    end

    @impl true
    def stream(%LLMRequest{} = request, _emit, opts), do: start(request, opts)

    @impl true
    def cancel(_execution_ref, _opts), do: :ok
  end

  test "ensure_conversation/1 starts once and then returns existing process" do
    assert {:ok, pid, :started} = Runtime.ensure_conversation(conversation_id: "runtime-conv-1")
    assert is_pid(pid)

    assert {:ok, ^pid, :existing} =
             Runtime.ensure_conversation(conversation_id: "runtime-conv-1")

    assert pid == Runtime.whereis("runtime-conv-1")

    assert {:ok, _conversation, _directives} =
             Runtime.send_user_message("runtime-conv-1", "hello runtime")

    assert {:ok, derived} = Runtime.derived_state("runtime-conv-1")
    assert derived.last_user_message == "hello runtime"

    assert :ok = Runtime.stop_conversation("runtime-conv-1")
    assert Runtime.whereis("runtime-conv-1") == nil
  end

  test "project-scoped conversations with same id are isolated by project id" do
    assert {:ok, pid_a, :started} =
             Runtime.ensure_conversation(project_id: "project-a", conversation_id: "shared-conv")

    assert {:ok, pid_b, :started} =
             Runtime.ensure_conversation(project_id: "project-b", conversation_id: "shared-conv")

    assert pid_a != pid_b

    assert pid_a == Runtime.whereis({"project-a", "shared-conv"})
    assert pid_b == Runtime.whereis({"project-b", "shared-conv"})

    assert {:ok, conversation_a, _} =
             Runtime.send_user_message({"project-a", "shared-conv"}, "from A")

    assert {:ok, conversation_b, _} =
             Runtime.send_user_message({"project-b", "shared-conv"}, "from B")

    assert Conversation.derived_state(conversation_a).last_user_message == "from A"
    assert Conversation.derived_state(conversation_b).last_user_message == "from B"

    assert :ok = Runtime.stop_conversation({"project-a", "shared-conv"})
    assert :ok = Runtime.stop_conversation({"project-b", "shared-conv"})

    assert Runtime.whereis({"project-a", "shared-conv"}) == nil
    assert Runtime.whereis({"project-b", "shared-conv"}) == nil
  end

  test "start_conversation/1 validates required conversation id" do
    assert {:error, {:conversation_id, :missing}} = Runtime.start_conversation([])

    assert {:error, {:conversation_id, :blank}} =
             Runtime.start_conversation(conversation_id: "  ")
  end

  test "stop_conversation/1 returns not_found when no process is registered" do
    assert {:error, :not_found} == Runtime.stop_conversation("does-not-exist")
  end

  test "send_user_message/3 auto-starts a missing conversation" do
    assert Runtime.whereis("runtime-conv-auto") == nil

    assert {:ok, conversation, _directives} =
             Runtime.send_user_message("runtime-conv-auto", "auto start")

    assert Conversation.derived_state(conversation).last_user_message == "auto start"

    assert {:ok, timeline} = Runtime.timeline("runtime-conv-auto")

    assert Enum.any?(
             timeline,
             &(&1.kind == :message and &1.role == :user and &1.content == "auto start")
           )

    assert :ok = Runtime.stop_conversation("runtime-conv-auto")
  end

  test "record_assistant_message/3 auto-starts and updates conversation" do
    assert Runtime.whereis("runtime-conv-assistant") == nil

    assert {:ok, _conversation, _directives} =
             Runtime.send_user_message("runtime-conv-assistant", "hello from runtime")

    assert {:ok, conversation, _directives} =
             Runtime.record_assistant_message("runtime-conv-assistant", "runtime assistant reply")

    derived = Conversation.derived_state(conversation)

    assert Enum.map(derived.messages, & &1.content) == [
             "hello from runtime",
             "runtime assistant reply"
           ]

    assert :ok = Runtime.stop_conversation("runtime-conv-assistant")
  end

  test "generate_assistant_reply/2 routes through managed runtime by locator" do
    assert {:ok, _conversation, _directives} =
             Runtime.send_user_message("runtime-conv-generate", "hello runtime")

    assert {:ok, generation_ref} =
             Runtime.generate_assistant_reply("runtime-conv-generate",
               llm: %{backend: :runtime_fast_stub},
               llm_config: llm_config(:runtime_fast_stub, FastRuntimeBackendStub),
               backend_opts: [test_pid: self()]
             )

    assert_receive {:runtime_fast_backend_called, _request_id}

    assert_receive {:jido_conversation,
                    {:generation_result, ^generation_ref, {:ok, %LLMResult{} = result}}}

    assert result.text == "runtime fast reply"

    assert {:ok, derived} = Runtime.derived_state("runtime-conv-generate")
    assert Enum.map(derived.messages, & &1.content) == ["hello runtime", "runtime fast reply"]

    assert :ok = Runtime.stop_conversation("runtime-conv-generate")
  end

  test "cancel_generation/2 routes through managed runtime by locator" do
    assert {:ok, _conversation, _directives} =
             Runtime.send_user_message("runtime-conv-cancel", "please wait")

    assert {:ok, generation_ref} =
             Runtime.generate_assistant_reply("runtime-conv-cancel",
               llm: %{backend: :runtime_slow_stub},
               llm_config: llm_config(:runtime_slow_stub, SlowRuntimeBackendStub),
               backend_opts: [test_pid: self(), sleep_ms: 2_000]
             )

    assert_receive {:runtime_slow_backend_started, _request_id}

    assert :ok = Runtime.cancel_generation("runtime-conv-cancel", "runtime_cancel")
    assert_receive {:jido_conversation, {:generation_canceled, ^generation_ref, "runtime_cancel"}}

    refute_receive {:jido_conversation, {:generation_result, ^generation_ref, _}}, 150

    assert {:ok, derived} = Runtime.derived_state("runtime-conv-cancel")
    assert derived.status == :canceled
    assert derived.cancel_reason == "runtime_cancel"

    assert :ok = Runtime.stop_conversation("runtime-conv-cancel")
  end

  test "read and cancel APIs return locator errors" do
    assert {:error, :invalid_locator} = Runtime.conversation("")
    assert {:error, :invalid_locator} = Runtime.derived_state({"", "conv"})
    assert {:error, :invalid_locator} = Runtime.record_assistant_message("", "bad locator")
    assert {:error, :invalid_locator} = Runtime.cancel_generation({"project", ""})

    assert {:error, :not_found} = Runtime.conversation("missing-runtime-conv")
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
