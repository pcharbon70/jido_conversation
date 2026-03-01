defmodule JidoConversation.ModePhase2IntegrationTest do
  use ExUnit.Case, async: false

  alias JidoConversation
  alias JidoConversation.LLM.Backend
  alias JidoConversation.LLM.Request, as: LLMRequest
  alias JidoConversation.LLM.Result, as: LLMResult

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
      send(
        Keyword.get(opts, :test_pid, self()),
        {:mode_phase2_slow_backend_started, request.request_id}
      )

      Process.sleep(Keyword.get(opts, :sleep_ms, 1_500))

      {:ok,
       LLMResult.new!(%{
         request_id: request.request_id,
         conversation_id: request.conversation_id,
         backend: request.backend,
         status: :completed,
         text: "phase2 slow reply",
         provider: request.provider || "anthropic",
         model: request.model || "claude-test"
       })}
    end

    @impl true
    def stream(%LLMRequest{} = request, _emit, opts), do: start(request, opts)

    @impl true
    def cancel(_execution_ref, _opts), do: :ok
  end

  test "phase2 registry integration exposes deterministic supported mode metadata" do
    assert JidoConversation.supported_modes() == [:coding, :planning, :engineering]

    metadata = JidoConversation.supported_mode_metadata()

    assert Enum.map(metadata, & &1.id) == [:coding, :planning, :engineering]
    assert Enum.all?(metadata, &is_binary(&1.summary))
    assert Enum.all?(metadata, &is_map(&1.capabilities))
  end

  test "phase2 resolver integration applies precedence and normalization" do
    previous_defaults = Application.get_env(:jido_conversation, :mode_option_defaults, %{})

    on_exit(fn ->
      Application.put_env(:jido_conversation, :mode_option_defaults, previous_defaults)
    end)

    Application.put_env(:jido_conversation, :mode_option_defaults, %{
      planning: %{max_phases: "8"}
    })

    conversation_id = "phase2-mode-config-precedence"

    assert {:ok, _conversation, _directives} =
             JidoConversation.configure_mode(conversation_id, :planning,
               mode_state: %{"objective" => "Plan A", "max_phases" => "4"}
             )

    assert {:ok, derived} = JidoConversation.derived_state(conversation_id)
    assert derived.mode_state.objective == "Plan A"
    assert derived.mode_state.max_phases == 4

    assert {:ok, _conversation, _directives} =
             JidoConversation.configure_mode(conversation_id, :planning,
               mode_state: %{"objective" => "Plan B"}
             )

    assert {:ok, derived} = JidoConversation.derived_state(conversation_id)
    assert derived.mode_state.objective == "Plan B"
    assert derived.mode_state.max_phases == 4

    assert :ok = JidoConversation.stop_conversation(conversation_id)
  end

  test "phase2 resolver integration rejects invalid mode config" do
    conversation_id = "phase2-mode-config-invalid"

    assert {:error, {:invalid_mode_config, :planning, diagnostics}} =
             JidoConversation.configure_mode(conversation_id, :planning,
               mode_state: %{objective: "Plan X", unexpected: true}
             )

    assert Enum.any?(diagnostics, fn diagnostic ->
             diagnostic.code == :unknown_key and diagnostic.path == [:mode_state, :unexpected]
           end)

    assert :ok = JidoConversation.stop_conversation(conversation_id)
  end

  test "phase2 switching integration supports idle switch, rejects active switch, and forces switch with cancel reason" do
    conversation_id = "phase2-mode-switch-policy"

    assert {:ok, _conversation, _directives} =
             JidoConversation.configure_mode(conversation_id, :planning,
               mode_state: %{objective: "Initial planning"}
             )

    assert {:ok, :planning} = JidoConversation.mode(conversation_id)

    assert {:ok, _conversation, _directives} =
             JidoConversation.send_user_message(conversation_id, "please wait")

    assert {:ok, generation_ref} =
             JidoConversation.generate_assistant_reply(conversation_id,
               llm: %{backend: :mode_phase2_slow_stub},
               llm_config: llm_config(:mode_phase2_slow_stub, SlowBackendStub),
               backend_opts: [test_pid: self(), sleep_ms: 2_000]
             )

    assert_receive {:mode_phase2_slow_backend_started, _request_id}

    assert {:error, :run_in_progress} =
             JidoConversation.configure_mode(conversation_id, :engineering,
               mode_state: %{topic: "Architecture"}
             )

    assert {:ok, entries_after_reject} =
             JidoConversation.conversation_thread_entries(conversation_id)

    assert Enum.any?(entries_after_reject, fn entry ->
             event = entry.payload[:event] || entry.payload["event"]
             reason = entry.payload[:reason] || entry.payload["reason"]

             entry.kind == :note and event == "mode_switch_rejected" and
               reason == "run_in_progress"
           end)

    assert {:ok, _conversation, _directives} =
             JidoConversation.configure_mode(conversation_id, :engineering,
               force: true,
               cancel_reason: "phase2_force_switch",
               mode_state: %{topic: "Architecture"}
             )

    assert_receive {:jido_conversation,
                    {:generation_canceled, ^generation_ref, "phase2_force_switch"}}

    assert {:ok, :engineering} = JidoConversation.mode(conversation_id)

    assert {:ok, entries_after_force} =
             JidoConversation.conversation_thread_entries(conversation_id)

    assert Enum.any?(entries_after_force, fn entry ->
             event = entry.payload[:event] || entry.payload["event"]
             reason = entry.payload[:reason] || entry.payload["reason"]

             entry.kind == :note and event == "mode_switch_accepted" and
               reason == "forced_mode_switch"
           end)

    assert :ok = JidoConversation.stop_conversation(conversation_id)
  end

  defp llm_config(backend_id, module) do
    [
      default_backend: backend_id,
      default_stream?: false,
      default_timeout_ms: 30_000,
      default_provider: "anthropic",
      default_model: "claude-test",
      backends: [
        {backend_id,
         [
           module: module,
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
