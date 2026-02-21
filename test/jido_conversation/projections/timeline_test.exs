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

  test "preserves normalized output metadata for assistant and tool entries" do
    events = [
      signal(
        "conv.out.assistant.delta",
        %{
          output_id: "o1",
          channel: "web",
          delta: "Hi ",
          lifecycle: "progress",
          status: "streaming",
          backend: "jido_ai",
          provider: "anthropic",
          model: "claude",
          usage: %{input_tokens: 1},
          metadata: %{trace_id: "t1"}
        },
        "2"
      ),
      signal(
        "conv.out.assistant.completed",
        %{
          output_id: "o1",
          channel: "web",
          content: "Hi there",
          lifecycle: "completed",
          status: "completed",
          finish_reason: "stop"
        },
        "3"
      ),
      signal(
        "conv.out.tool.status",
        %{
          output_id: "tool-1",
          channel: "web",
          status: "started",
          message: "calling web_search",
          tool_name: "web_search",
          tool_call_id: "call-1"
        },
        "4"
      )
    ]

    timeline = Timeline.from_events(events, coalesce_deltas: false)

    delta = Enum.at(timeline, 0)
    assert delta.metadata.status == "streaming"
    assert delta.metadata.backend == "jido_ai"
    assert delta.metadata.provider == "anthropic"
    assert delta.metadata.usage == %{input_tokens: 1}
    assert delta.metadata.metadata == %{trace_id: "t1"}

    completed = Enum.at(timeline, 1)
    assert completed.metadata.status == "completed"
    assert completed.metadata.finish_reason == "stop"

    tool = Enum.at(timeline, 2)
    assert tool.metadata.status == "started"
    assert tool.metadata.tool_name == "web_search"
    assert tool.metadata.tool_call_id == "call-1"
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
