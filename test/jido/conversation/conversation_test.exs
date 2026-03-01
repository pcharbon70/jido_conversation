defmodule Jido.ConversationTest do
  use ExUnit.Case, async: true

  alias Jido.Conversation

  test "new/1 initializes conversation state and thread" do
    conversation = Conversation.new(conversation_id: "conv-1")

    assert conversation.state.conversation_id == "conv-1"
    assert conversation.state.status == :idle

    thread = Conversation.thread(conversation)
    assert thread != nil
    assert thread.id == "conv_thread_conv-1"
  end

  test "send_user_message/3 syncs state from thread" do
    conversation = Conversation.new(conversation_id: "conv-2")

    assert {:ok, conversation, _directives} =
             Conversation.send_user_message(conversation, "hello", metadata: %{channel: "cli"})

    derived = Conversation.derived_state(conversation)

    assert derived.status == :pending_llm
    assert derived.turn == 1
    assert derived.last_user_message == "hello"
    assert length(derived.messages) == 1

    [message] = derived.messages
    assert message.role == :user
    assert message.content == "hello"
  end

  test "record_assistant_message/3 is included in llm context" do
    conversation = Conversation.new(conversation_id: "conv-3")

    {:ok, conversation, _} = Conversation.send_user_message(conversation, "How are you?")

    {:ok, conversation, _} =
      Conversation.record_assistant_message(conversation, "Doing well.")

    context = Conversation.llm_context(conversation)

    assert Enum.map(context, & &1.role) == [:user, :assistant]
    assert Enum.map(context, & &1.content) == ["How are you?", "Doing well."]
  end

  test "cancel/2 marks conversation as canceled and appears in timeline" do
    conversation = Conversation.new(conversation_id: "conv-4")

    assert {:ok, conversation, _directives} = Conversation.cancel(conversation, "user_abort")

    assert conversation.state.status == :canceled
    assert conversation.state.cancel_requested?
    assert conversation.state.cancel_reason == "user_abort"

    timeline = Conversation.timeline(conversation)

    assert Enum.any?(timeline, fn entry ->
             entry.kind == :status and entry.metadata[:event] == "cancel_requested"
           end)
  end

  test "configure_llm/3 updates derived llm settings" do
    conversation = Conversation.new(conversation_id: "conv-5")

    assert {:ok, conversation, _directives} =
             Conversation.configure_llm(conversation, :jido_ai,
               provider: "anthropic",
               model: "claude-3-opus",
               options: %{temperature: 0.2}
             )

    derived = Conversation.derived_state(conversation)

    assert derived.llm.backend == :jido_ai
    assert derived.llm.provider == "anthropic"
    assert derived.llm.model == "claude-3-opus"
    assert derived.llm.options == %{temperature: 0.2}
  end

  test "configure_skills/2 updates derived skills and timeline" do
    conversation = Conversation.new(conversation_id: "conv-5-skills")

    assert {:ok, conversation, _directives} =
             Conversation.configure_skills(conversation, [
               "web_search",
               :code_exec,
               "  ",
               "web_search"
             ])

    derived = Conversation.derived_state(conversation)
    assert derived.skills.enabled == ["web_search", "code_exec"]

    timeline = Conversation.timeline(conversation)

    assert Enum.any?(timeline, fn entry ->
             entry.kind == :status and entry.metadata[:event] == "skills_configured"
           end)
  end

  test "send_user_message/3 rejects empty content" do
    conversation = Conversation.new(conversation_id: "conv-6")

    assert {:error, :empty_message} == Conversation.send_user_message(conversation, "  ")
  end

  test "mode defaults to :coding with empty run tracking" do
    conversation = Conversation.new(conversation_id: "conv-mode-default")

    assert :coding == Conversation.mode(conversation)

    derived = Conversation.derived_state(conversation)
    assert derived.mode == :coding
    assert derived.mode_state == %{}
    assert derived.active_run == nil
    assert derived.run_history == []
  end

  test "configure_mode/3 updates derived mode state and timeline" do
    conversation = Conversation.new(conversation_id: "conv-mode-config")

    assert {:ok, conversation, _directives} =
             Conversation.configure_mode(conversation, :coding,
               mode_state: %{pipeline: "default", interruptible: true}
             )

    assert :coding == Conversation.mode(conversation)

    derived = Conversation.derived_state(conversation)
    assert derived.mode == :coding
    assert derived.mode_state == %{pipeline: "default", interruptible: true}

    entries = Conversation.thread_entries(conversation)

    assert Enum.any?(entries, fn entry ->
             event = entry.payload[:event] || entry.payload["event"]
             entry.kind == :note and event == "mode_configured"
           end)
  end

  test "configure_mode/3 rejects unsupported mode" do
    conversation = Conversation.new(conversation_id: "conv-mode-invalid")

    assert {:error, {:unsupported_mode, :unknown, [:coding, :planning, :engineering]}} =
             Conversation.configure_mode(conversation, :unknown)
  end

  test "configure_mode/3 validates required options and normalizes values" do
    conversation = Conversation.new(conversation_id: "conv-mode-planning")

    assert {:error, {:invalid_mode_config, :planning, diagnostics}} =
             Conversation.configure_mode(conversation, :planning)

    assert Enum.any?(diagnostics, fn diagnostic ->
             diagnostic.code == :required and diagnostic.path == [:mode_state, :objective]
           end)

    assert {:ok, conversation, _directives} =
             Conversation.configure_mode(conversation, :planning,
               mode_state: %{"objective" => "Ship phase 1", "max_phases" => "4"}
             )

    derived = Conversation.derived_state(conversation)
    assert derived.mode == :planning
    assert derived.mode_state.objective == "Ship phase 1"
    assert derived.mode_state.max_phases == 4
    assert derived.mode_state.output_format == :markdown
  end

  test "configure_mode/3 emits accepted switch audit metadata" do
    conversation = Conversation.new(conversation_id: "conv-mode-audit")

    assert {:ok, conversation, _directives} =
             Conversation.configure_mode(conversation, :planning,
               cause_id: "cause-mode-audit",
               reason: "manual_switch",
               mode_state: %{objective: "Audit this switch"}
             )

    entries = Conversation.thread_entries(conversation)

    assert Enum.any?(entries, fn entry ->
             event = entry.payload[:event] || entry.payload["event"]

             entry.kind == :note and
               event == "mode_switch_accepted" and
               (entry.payload[:cause_id] || entry.payload["cause_id"]) == "cause-mode-audit" and
               (entry.payload[:from_mode] || entry.payload["from_mode"]) == :coding and
               (entry.payload[:to_mode] || entry.payload["to_mode"]) == :planning
           end)

    assert Enum.any?(entries, fn entry ->
             event = entry.payload[:event] || entry.payload["event"]

             entry.kind == :note and
               event == "mode_configured" and
               (entry.payload[:cause_id] || entry.payload["cause_id"]) == "cause-mode-audit"
           end)
  end
end
