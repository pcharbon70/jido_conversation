defmodule JidoConversation.ConversationRefTest do
  use ExUnit.Case, async: true

  alias JidoConversation.ConversationRef

  test "builds and parses canonical project-scoped subject" do
    assert {:ok, ref} = ConversationRef.new("project-a", "conversation-1")

    assert ref.subject ==
             "project/project-a/conversation/conversation-1"

    assert {:ok, parsed} = ConversationRef.parse_subject(ref.subject)
    assert parsed.project_id == "project-a"
    assert parsed.conversation_id == "conversation-1"
  end

  test "url-encodes and decodes ids with reserved characters" do
    project_id = "project / one"
    conversation_id = "conversation:alpha/beta"

    subject = ConversationRef.subject(project_id, conversation_id)

    assert subject ==
             "project/project+%2F+one/conversation/conversation%3Aalpha%2Fbeta"

    assert {:ok, parsed} = ConversationRef.parse_subject(subject)
    assert parsed.project_id == project_id
    assert parsed.conversation_id == conversation_id
  end

  test "returns error for invalid subject format" do
    assert {:error, {:invalid_subject, "conversation-1"}} =
             ConversationRef.parse_subject("conversation-1")
  end
end
