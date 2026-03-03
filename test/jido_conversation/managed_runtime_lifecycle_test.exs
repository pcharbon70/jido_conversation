defmodule Jido.Conversation.ManagedRuntimeLifecycleTest do
  use ExUnit.Case, async: false

  test "start_conversation/1 starts once and duplicate start returns already_started" do
    conversation_id = unique_id("conversation")

    assert {:ok, pid} =
             Jido.Conversation.Runtime.start_conversation(conversation_id: conversation_id)

    assert {:error, {:already_started, ^pid}} =
             Jido.Conversation.Runtime.start_conversation(conversation_id: conversation_id)

    assert pid == Jido.Conversation.Runtime.whereis(conversation_id)
    assert :ok = Jido.Conversation.Runtime.stop_conversation(conversation_id)
  end

  test "ensure_conversation/1 reports existing status after first start" do
    conversation_id = unique_id("conversation")

    assert {:ok, pid, :started} =
             Jido.Conversation.Runtime.ensure_conversation(%{conversation_id: conversation_id})

    assert {:ok, ^pid, :existing} =
             Jido.Conversation.Runtime.ensure_conversation(conversation_id: conversation_id)

    assert :ok = Jido.Conversation.Runtime.stop_conversation(conversation_id)
  end

  test "start_conversation/1 supports project-scoped locators and metadata merge" do
    project_id = unique_id("project")
    conversation_id = unique_id("conversation")
    locator = {project_id, conversation_id}

    assert {:ok, pid} =
             Jido.Conversation.Runtime.start_conversation(
               project_id: project_id,
               conversation_id: conversation_id,
               metadata: %{channel: "cli"}
             )

    assert pid == Jido.Conversation.Runtime.whereis(locator)
    assert {:ok, conversation} = Jido.Conversation.Runtime.conversation(locator)
    assert is_map(conversation)
    assert conversation.state.metadata.project_id == project_id
    assert conversation.state.metadata.channel == "cli"

    assert :ok = Jido.Conversation.Runtime.stop_conversation(locator)
  end

  test "start and ensure validate malformed options" do
    assert {:error, {:conversation_id, :missing}} =
             Jido.Conversation.Runtime.start_conversation(%{})

    assert {:error, {:conversation_id, :blank}} =
             Jido.Conversation.Runtime.start_conversation(conversation_id: " ")

    assert {:error, {:project_id, :blank}} =
             Jido.Conversation.Runtime.start_conversation(
               project_id: " ",
               conversation_id: unique_id("conversation")
             )

    assert {:error, {:invalid_metadata, :expected_map}} =
             Jido.Conversation.Runtime.start_conversation(
               conversation_id: unique_id("conversation"),
               metadata: "bad"
             )

    assert {:error, {:invalid_state, :expected_map}} =
             Jido.Conversation.Runtime.start_conversation(
               conversation_id: unique_id("conversation"),
               state: :bad
             )

    assert {:error, {:conversation_id, :missing}} =
             Jido.Conversation.Runtime.ensure_conversation("bad_opts")
  end

  test "managed runtime APIs return invalid-locator and not-found errors consistently" do
    missing_conversation_id = unique_id("missing")

    assert nil == Jido.Conversation.Runtime.whereis("")
    assert nil == Jido.Conversation.Runtime.whereis({"project", ""})

    assert {:error, :invalid_locator} = Jido.Conversation.Runtime.derived_state("")
    assert {:error, :invalid_locator} = Jido.Conversation.Runtime.timeline("")
    assert {:error, :invalid_locator} = Jido.Conversation.Runtime.send_user_message("", "hello")
    assert {:error, :invalid_locator} = Jido.Conversation.Runtime.configure_skills("", [])

    assert {:error, :invalid_locator} =
             Jido.Conversation.Runtime.generate_assistant_reply({"project", ""})

    assert {:error, :invalid_locator} = Jido.Conversation.Runtime.stop_conversation("")

    assert {:error, :not_found} =
             Jido.Conversation.Runtime.stop_conversation(missing_conversation_id)

    assert {:error, :not_found} =
             Jido.Conversation.Runtime.cancel_generation(missing_conversation_id)
  end

  defp unique_id(prefix) do
    "#{prefix}-#{System.unique_integer([:positive, :monotonic])}"
  end
end
