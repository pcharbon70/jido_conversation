defmodule JidoConversation.ManagedRuntimeLifecycleTest do
  use ExUnit.Case, async: false

  alias JidoConversation

  test "start_conversation/1 starts once and duplicate start returns already_started" do
    conversation_id = unique_id("conversation")

    assert {:ok, pid} = JidoConversation.start_conversation(conversation_id: conversation_id)

    assert {:error, {:already_started, ^pid}} =
             JidoConversation.start_conversation(conversation_id: conversation_id)

    assert pid == JidoConversation.whereis_conversation(conversation_id)
    assert :ok = JidoConversation.stop_conversation(conversation_id)
  end

  test "ensure_conversation/1 reports existing status after first start" do
    conversation_id = unique_id("conversation")

    assert {:ok, pid, :started} =
             JidoConversation.ensure_conversation(%{conversation_id: conversation_id})

    assert {:ok, ^pid, :existing} =
             JidoConversation.ensure_conversation(conversation_id: conversation_id)

    assert :ok = JidoConversation.stop_conversation(conversation_id)
  end

  test "start_conversation/1 supports project-scoped locators and metadata merge" do
    project_id = unique_id("project")
    conversation_id = unique_id("conversation")
    locator = {project_id, conversation_id}

    assert {:ok, pid} =
             JidoConversation.start_conversation(
               project_id: project_id,
               conversation_id: conversation_id,
               metadata: %{channel: "cli"}
             )

    assert pid == JidoConversation.whereis_conversation(locator)
    assert {:ok, conversation} = JidoConversation.conversation(locator)
    assert is_map(conversation)
    assert conversation.state.metadata.project_id == project_id
    assert conversation.state.metadata.channel == "cli"

    assert :ok = JidoConversation.stop_conversation(locator)
  end

  test "start and ensure validate malformed options" do
    assert {:error, {:conversation_id, :missing}} = JidoConversation.start_conversation(%{})

    assert {:error, {:conversation_id, :blank}} =
             JidoConversation.start_conversation(conversation_id: " ")

    assert {:error, {:project_id, :blank}} =
             JidoConversation.start_conversation(
               project_id: " ",
               conversation_id: unique_id("conversation")
             )

    assert {:error, {:invalid_metadata, :expected_map}} =
             JidoConversation.start_conversation(
               conversation_id: unique_id("conversation"),
               metadata: "bad"
             )

    assert {:error, {:invalid_state, :expected_map}} =
             JidoConversation.start_conversation(
               conversation_id: unique_id("conversation"),
               state: :bad
             )

    assert {:error, {:conversation_id, :missing}} =
             JidoConversation.ensure_conversation("bad_opts")
  end

  test "managed runtime APIs return invalid-locator and not-found errors consistently" do
    missing_conversation_id = unique_id("missing")

    assert nil == JidoConversation.whereis_conversation("")
    assert nil == JidoConversation.whereis_conversation({"project", ""})

    assert {:error, :invalid_locator} = JidoConversation.derived_state("")
    assert {:error, :invalid_locator} = JidoConversation.conversation_timeline("")
    assert {:error, :invalid_locator} = JidoConversation.send_user_message("", "hello")
    assert {:error, :invalid_locator} = JidoConversation.configure_skills("", [])
    assert {:error, :invalid_locator} = JidoConversation.generate_assistant_reply({"project", ""})
    assert {:error, :invalid_locator} = JidoConversation.stop_conversation("")

    assert {:error, :not_found} = JidoConversation.stop_conversation(missing_conversation_id)
    assert {:error, :not_found} = JidoConversation.cancel_generation(missing_conversation_id)
  end

  defp unique_id(prefix) do
    "#{prefix}-#{System.unique_integer([:positive, :monotonic])}"
  end
end
