defmodule Jido.Conversation.RuntimeTest do
  use ExUnit.Case, async: false

  alias Jido.Conversation
  alias Jido.Conversation.Runtime
  alias Jido.Conversation.Server

  test "ensure_conversation/1 starts once and then returns existing process" do
    assert {:ok, pid, :started} = Runtime.ensure_conversation(conversation_id: "runtime-conv-1")
    assert is_pid(pid)

    assert {:ok, ^pid, :existing} =
             Runtime.ensure_conversation(conversation_id: "runtime-conv-1")

    assert pid == Runtime.whereis("runtime-conv-1")

    assert {:ok, _conversation, _directives} =
             Server.send_user_message(pid, "hello runtime")

    derived = Server.derived_state(pid)
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

    assert {:ok, conversation_a, _} = Server.send_user_message(pid_a, "from A")
    assert {:ok, conversation_b, _} = Server.send_user_message(pid_b, "from B")

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
end
