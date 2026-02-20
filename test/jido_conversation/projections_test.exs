defmodule JidoConversation.ProjectionsTest do
  use ExUnit.Case, async: false

  alias JidoConversation.Ingest.Adapters.Messaging
  alias JidoConversation.Ingest.Adapters.Outbound
  alias JidoConversation.Projections

  test "timeline and llm_context projections can be built from conversation id" do
    conversation_id = unique_id("conversation")
    output_id = unique_id("output")

    assert {:ok, _} =
             Messaging.ingest_received(
               conversation_id,
               unique_id("msg"),
               "slack",
               %{text: "hello world"}
             )

    assert {:ok, _} =
             Outbound.emit_assistant_delta(
               conversation_id,
               output_id,
               "web",
               "hi "
             )

    assert {:ok, _} =
             Outbound.emit_assistant_completed(
               conversation_id,
               output_id,
               "web",
               "hi there"
             )

    timeline = Projections.timeline(conversation_id)
    context = Projections.llm_context(conversation_id)

    assert Enum.any?(timeline, &(&1.type == "conv.in.message.received"))
    assert Enum.any?(timeline, &(&1.type == "conv.out.assistant.completed"))
    assert Enum.any?(context, &(&1.role == :user))
    assert Enum.any?(context, &(&1.role == :assistant))
  end

  defp unique_id(prefix) do
    "#{prefix}-#{System.unique_integer([:positive, :monotonic])}"
  end
end
