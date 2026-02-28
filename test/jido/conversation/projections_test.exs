defmodule Jido.Conversation.ProjectionsTest do
  use ExUnit.Case, async: true

  alias Jido.Conversation.Projections.LlmContext
  alias Jido.Conversation.Projections.Timeline
  alias Jido.Thread

  test "timeline and llm context project thread messages" do
    thread =
      Thread.new(id: "thread-2")
      |> Thread.append(%{kind: :message, payload: %{role: "user", content: "A"}})
      |> Thread.append(%{kind: :message, payload: %{role: "assistant", content: "B"}})
      |> Thread.append(%{kind: :note, payload: %{event: "cancel_requested", reason: "stop"}})

    entries = Thread.to_list(thread)
    timeline = Timeline.from_entries(entries)
    context = LlmContext.from_entries(entries)

    assert Enum.map(timeline, & &1.kind) == [:message, :message, :status]
    assert Enum.map(context, & &1.role) == [:user, :assistant]
    assert Enum.map(context, & &1.content) == ["A", "B"]
  end
end
