defmodule JidoConversation.Projections.TimelineTest do
  use ExUnit.Case, async: true

  alias Jido.Signal
  alias JidoConversation.Projections.Timeline

  test "builds timeline entries and coalesces adjacent assistant deltas" do
    events = [
      signal(
        "conv.in.message.received",
        %{message_id: "m1", ingress: "slack", text: "hello"},
        "1"
      ),
      signal("conv.out.assistant.delta", %{output_id: "o1", channel: "web", delta: "Hi "}, "2"),
      signal("conv.out.assistant.delta", %{output_id: "o1", channel: "web", delta: "there"}, "3"),
      signal(
        "conv.out.assistant.completed",
        %{output_id: "o1", channel: "web", content: "Hi there"},
        "4"
      )
    ]

    timeline = Timeline.from_events(events)

    assert length(timeline) == 3

    assert Enum.at(timeline, 0).role == :user
    assert Enum.at(timeline, 0).content == "hello"

    delta_entry = Enum.at(timeline, 1)
    assert delta_entry.role == :assistant
    assert delta_entry.kind == :delta
    assert delta_entry.content == "Hi there"
    assert delta_entry.event_ids == ["2", "3"]

    completed_entry = Enum.at(timeline, 2)
    assert completed_entry.role == :assistant
    assert completed_entry.kind == :message
    assert completed_entry.content == "Hi there"
  end

  test "can keep raw delta entries when coalescing is disabled" do
    events = [
      signal("conv.out.assistant.delta", %{output_id: "o1", channel: "web", delta: "a"}, "2"),
      signal("conv.out.assistant.delta", %{output_id: "o1", channel: "web", delta: "b"}, "3")
    ]

    timeline = Timeline.from_events(events, coalesce_deltas: false)

    assert Enum.map(timeline, & &1.content) == ["a", "b"]
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
