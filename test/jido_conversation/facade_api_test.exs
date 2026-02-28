defmodule JidoConversation.FacadeApiTest do
  use ExUnit.Case, async: false

  test "ingest/2 accepts contract attrs and projection wrappers expose results" do
    conversation_id = unique_id("conversation")

    assert {:ok, %{status: :published, signal: signal}} =
             JidoConversation.ingest(%{
               type: "conv.in.message.received",
               source: "/messaging/web",
               conversation_id: conversation_id,
               data: %{
                 message_id: unique_id("msg"),
                 ingress: "web",
                 text: "hello from facade"
               },
               extensions: %{contract_major: 1}
             })

    assert signal.type == "conv.in.message.received"

    timeline = JidoConversation.timeline(conversation_id)
    context = JidoConversation.llm_context(conversation_id)

    assert Enum.any?(timeline, &(&1.type == "conv.in.message.received"))
    assert Enum.any?(context, &(&1.role == :user and &1.content == "hello from facade"))
  end

  test "project-scoped timeline/3 and llm_context/3 wrappers isolate same conversation id" do
    conversation_id = unique_id("conversation")
    project_a = unique_id("project")
    project_b = unique_id("project")

    assert {:ok, _} =
             JidoConversation.ingest(%{
               type: "conv.in.message.received",
               source: "/messaging/web",
               project_id: project_a,
               conversation_id: conversation_id,
               data: %{message_id: unique_id("msg"), ingress: "web", text: "hello from a"},
               extensions: %{contract_major: 1}
             })

    assert {:ok, _} =
             JidoConversation.ingest(%{
               type: "conv.in.message.received",
               source: "/messaging/web",
               project_id: project_b,
               conversation_id: conversation_id,
               data: %{message_id: unique_id("msg"), ingress: "web", text: "hello from b"},
               extensions: %{contract_major: 1}
             })

    timeline_a = JidoConversation.timeline(project_a, conversation_id, [])
    timeline_b = JidoConversation.timeline(project_b, conversation_id, [])

    assert length(timeline_a) == 1
    assert length(timeline_b) == 1
    assert hd(timeline_a).content == "hello from a"
    assert hd(timeline_b).content == "hello from b"

    context_a = JidoConversation.llm_context(project_a, conversation_id, [])
    context_b = JidoConversation.llm_context(project_b, conversation_id, [])

    assert [%{content: "hello from a", role: :user}] = context_a
    assert [%{content: "hello from b", role: :user}] = context_b
  end

  test "telemetry_snapshot/0 exposes runtime telemetry shape" do
    snapshot = JidoConversation.telemetry_snapshot()

    assert is_map(snapshot)
    assert Map.has_key?(snapshot, :queue_depth)
    assert Map.has_key?(snapshot, :apply_latency_ms)
    assert Map.has_key?(snapshot, :abort_latency_ms)
    assert Map.has_key?(snapshot, :llm)
    assert is_map(snapshot.llm)
    assert Map.has_key?(snapshot.llm, :lifecycle_counts)
    assert Map.has_key?(snapshot.llm, :retry_by_category)
  end

  test "ingest/2 returns contract validation errors for invalid payloads" do
    assert {:error, {:contract_invalid, _reason}} = JidoConversation.ingest(%{type: "invalid"})
  end

  defp unique_id(prefix) do
    "#{prefix}-#{System.unique_integer([:positive, :monotonic])}"
  end
end
