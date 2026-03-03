defmodule Jido.Conversation.ManagedRuntimeLifecycleTest do
  use ExUnit.Case, async: false

  alias Jido.Conversation.Runtime

  test "start_conversation/1 starts once and duplicate start returns already_started" do
    conversation_id = unique_id("conversation")

    assert {:ok, pid} =
             Runtime.start_conversation(conversation_id: conversation_id)

    assert {:error, {:already_started, ^pid}} =
             Runtime.start_conversation(conversation_id: conversation_id)

    assert pid == Runtime.whereis(conversation_id)
    assert :ok = Runtime.stop_conversation(conversation_id)
  end

  test "ensure_conversation/1 reports existing status after first start" do
    conversation_id = unique_id("conversation")

    assert {:ok, pid, :started} =
             Runtime.ensure_conversation(%{conversation_id: conversation_id})

    assert {:ok, ^pid, :existing} =
             Runtime.ensure_conversation(conversation_id: conversation_id)

    assert :ok = Runtime.stop_conversation(conversation_id)
  end

  test "start_conversation/1 supports project-scoped locators and metadata merge" do
    project_id = unique_id("project")
    conversation_id = unique_id("conversation")
    locator = {project_id, conversation_id}

    assert {:ok, pid} =
             Runtime.start_conversation(
               project_id: project_id,
               conversation_id: conversation_id,
               metadata: %{channel: "cli"}
             )

    assert pid == Runtime.whereis(locator)
    assert {:ok, conversation} = Runtime.conversation(locator)
    assert is_map(conversation)
    assert conversation.state.metadata.project_id == project_id
    assert conversation.state.metadata.channel == "cli"

    assert :ok = Runtime.stop_conversation(locator)
  end

  test "start and ensure validate malformed options" do
    assert {:error, {:conversation_id, :missing}} =
             Runtime.start_conversation(%{})

    assert {:error, {:conversation_id, :blank}} =
             Runtime.start_conversation(conversation_id: " ")

    assert {:error, {:project_id, :blank}} =
             Runtime.start_conversation(
               project_id: " ",
               conversation_id: unique_id("conversation")
             )

    assert {:error, {:invalid_metadata, :expected_map}} =
             Runtime.start_conversation(
               conversation_id: unique_id("conversation"),
               metadata: "bad"
             )

    assert {:error, {:invalid_state, :expected_map}} =
             Runtime.start_conversation(
               conversation_id: unique_id("conversation"),
               state: :bad
             )

    assert {:error, {:conversation_id, :missing}} =
             Runtime.ensure_conversation("bad_opts")
  end

  test "managed runtime APIs return invalid-locator and not-found errors consistently" do
    missing_conversation_id = unique_id("missing")

    assert nil == Runtime.whereis("")
    assert nil == Runtime.whereis({"project", ""})

    assert {:error, :invalid_locator} = Runtime.derived_state("")
    assert {:error, :invalid_locator} = Runtime.timeline("")
    assert {:error, :invalid_locator} = Runtime.send_user_message("", "hello")
    assert {:error, :invalid_locator} = Runtime.configure_skills("", [])

    assert {:error, :invalid_locator} =
             Runtime.generate_assistant_reply({"project", ""})

    assert {:error, :invalid_locator} = Runtime.stop_conversation("")

    assert {:error, :not_found} =
             Runtime.stop_conversation(missing_conversation_id)

    assert {:error, :not_found} =
             Runtime.cancel_generation(missing_conversation_id)
  end

  defp unique_id(prefix) do
    "#{prefix}-#{System.unique_integer([:positive, :monotonic])}"
  end
end
