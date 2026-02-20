defmodule JidoConversation.Projections.LlmContextTest do
  use ExUnit.Case, async: true

  alias Jido.Signal
  alias JidoConversation.Projections.LlmContext

  test "builds role/content context from projected events" do
    events = [
      signal(
        "conv.in.message.received",
        %{message_id: "m1", ingress: "slack", text: "hello"},
        "1"
      ),
      signal("conv.out.assistant.delta", %{output_id: "o1", channel: "web", delta: "Hi "}, "2"),
      signal(
        "conv.out.assistant.completed",
        %{output_id: "o1", channel: "web", content: "Hi there"},
        "3"
      ),
      signal(
        "conv.out.tool.status",
        %{output_id: "t1", channel: "web", status: "completed", message: "tool done"},
        "4"
      )
    ]

    context = LlmContext.from_events(events)

    assert Enum.map(context, & &1.role) == [:user, :assistant, :tool]
    assert Enum.map(context, & &1.content) == ["hello", "Hi there", "tool done"]
  end

  test "optionally includes assistant deltas and applies max message cap" do
    events = [
      signal("conv.in.message.received", %{message_id: "m1", ingress: "slack", text: "a"}, "1"),
      signal("conv.out.assistant.delta", %{output_id: "o1", channel: "web", delta: "b"}, "2"),
      signal(
        "conv.out.assistant.completed",
        %{output_id: "o1", channel: "web", content: "c"},
        "3"
      )
    ]

    context = LlmContext.from_events(events, include_deltas: true, max_messages: 2)

    assert Enum.map(context, & &1.content) == ["b", "c"]
  end

  defp signal(type, data, id) do
    Signal.new!(type, data,
      id: id,
      source: "/tests/projections",
      subject: "conversation-1",
      extensions: %{"contract_major" => 1}
    )
  end
end
