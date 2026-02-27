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

  test "send_user_message/3 updates state and appends thread entries" do
    conversation = Conversation.new(conversation_id: "conv-2")

    assert {:ok, conversation, _directives} =
             Conversation.send_user_message(conversation, "hello", metadata: %{channel: "cli"})

    assert conversation.state.status == :pending_llm
    assert conversation.state.turn == 1
    assert length(conversation.state.messages) == 1

    assert Enum.any?(Conversation.thread_entries(conversation), fn entry ->
             entry.kind == :message and entry.payload[:role] == "user" and
               entry.payload[:content] == "hello"
           end)
  end

  test "cancel/2 marks conversation as canceled" do
    conversation = Conversation.new(conversation_id: "conv-3")

    assert {:ok, conversation, _directives} = Conversation.cancel(conversation, "user_abort")

    assert conversation.state.status == :canceled
    assert conversation.state.cancel_requested?
    assert conversation.state.cancel_reason == "user_abort"
  end

  test "configure_llm/3 sets backend/provider/model" do
    conversation = Conversation.new(conversation_id: "conv-4")

    assert {:ok, conversation, _directives} =
             Conversation.configure_llm(conversation, :jido_ai,
               provider: "anthropic",
               model: "claude-3-opus"
             )

    assert conversation.state.llm.backend == :jido_ai
    assert conversation.state.llm.provider == "anthropic"
    assert conversation.state.llm.model == "claude-3-opus"
  end

  test "send_user_message/3 rejects empty content" do
    conversation = Conversation.new(conversation_id: "conv-5")

    assert {:error, :empty_message} == Conversation.send_user_message(conversation, "  ")
  end
end
