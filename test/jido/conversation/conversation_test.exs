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

  test "send_user_message/3 rejects empty content" do
    conversation = Conversation.new(conversation_id: "conv-6")

    assert {:error, :empty_message} == Conversation.send_user_message(conversation, "  ")
  end
end
