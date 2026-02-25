defmodule JidoConversation.ProjectionsTest do
  use ExUnit.Case, async: false

  alias JidoConversation.Ingest
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

  test "project-scoped projections isolate same conversation id across projects" do
    conversation_id = unique_id("conversation")
    project_a = unique_id("project")
    project_b = unique_id("project")

    assert {:ok, _} =
             Ingest.ingest(%{
               type: "conv.in.message.received",
               source: "/messaging/web",
               project_id: project_a,
               conversation_id: conversation_id,
               data: %{message_id: unique_id("msg"), ingress: "web", text: "hello from a"},
               extensions: %{contract_major: 1}
             })

    assert {:ok, _} =
             Ingest.ingest(%{
               type: "conv.in.message.received",
               source: "/messaging/web",
               project_id: project_b,
               conversation_id: conversation_id,
               data: %{message_id: unique_id("msg"), ingress: "web", text: "hello from b"},
               extensions: %{contract_major: 1}
             })

    timeline_a = Projections.timeline(project_a, conversation_id, [])
    timeline_b = Projections.timeline(project_b, conversation_id, [])

    assert length(timeline_a) == 1
    assert length(timeline_b) == 1
    assert hd(timeline_a).content == "hello from a"
    assert hd(timeline_b).content == "hello from b"

    context_a = Projections.llm_context(project_a, conversation_id, [])
    context_b = Projections.llm_context(project_b, conversation_id, [])

    assert [%{content: "hello from a", role: :user}] = context_a
    assert [%{content: "hello from b", role: :user}] = context_b
  end

  defp unique_id(prefix) do
    "#{prefix}-#{System.unique_integer([:positive, :monotonic])}"
  end
end
