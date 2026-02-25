defmodule JidoConversation.Ingest.PipelineTest do
  use ExUnit.Case, async: false

  alias JidoConversation.ConversationRef
  alias JidoConversation.Ingest.Pipeline

  test "ingest persists to journal and publishes to bus" do
    conversation_id = unique_id("conversation")
    replay_start = DateTime.utc_now() |> DateTime.to_unix()

    attrs = %{
      type: "conv.in.message.received",
      source: "/messaging/slack",
      subject: conversation_id,
      data: %{message_id: unique_id("msg"), ingress: "slack"},
      extensions: %{contract_major: 1}
    }

    assert {:ok, %{status: :published, signal: signal, recorded: recorded}} =
             Pipeline.ingest(attrs)

    assert length(recorded) == 1
    assert hd(recorded).signal.id == signal.id

    conversation_events = Pipeline.conversation_events(conversation_id)
    assert Enum.count(conversation_events, &(&1.id == signal.id)) == 1
    assert Enum.count(conversation_events, &(&1.type == "conv.in.message.received")) == 1

    assert {:ok, replayed} = Pipeline.replay("conv.in.**", replay_start)
    assert Enum.any?(replayed, &(&1.signal.id == signal.id))
  end

  test "dedupe prevents duplicate publish for same subject and id" do
    conversation_id = unique_id("conversation")
    signal_id = unique_id("signal")

    attrs = %{
      id: signal_id,
      type: "conv.in.message.received",
      source: "/messaging/discord",
      subject: conversation_id,
      data: %{message_id: unique_id("msg"), ingress: "discord"},
      extensions: %{contract_major: 1}
    }

    assert {:ok, %{status: :published}} = Pipeline.ingest(attrs)
    assert {:ok, %{status: :duplicate, recorded: []}} = Pipeline.ingest(attrs)

    conversation_events = Pipeline.conversation_events(conversation_id)
    assert Enum.count(conversation_events, &(&1.id == signal_id)) == 1
    assert Enum.count(conversation_events, &(&1.type == "conv.in.message.received")) == 1
  end

  test "conversation_events/2 isolates same conversation id across projects" do
    project_a = unique_id("project")
    project_b = unique_id("project")
    conversation_id = unique_id("conversation")
    signal_id_a = unique_id("signal-a")
    signal_id_b = unique_id("signal-b")

    subject_a = ConversationRef.subject(project_a, conversation_id)
    subject_b = ConversationRef.subject(project_b, conversation_id)

    attrs_a = %{
      id: signal_id_a,
      type: "conv.in.message.received",
      source: "/messaging/web",
      subject: subject_a,
      data: %{message_id: unique_id("msg-a"), ingress: "web"},
      extensions: %{contract_major: 1, project_id: project_a}
    }

    attrs_b = %{
      id: signal_id_b,
      type: "conv.in.message.received",
      source: "/messaging/web",
      subject: subject_b,
      data: %{message_id: unique_id("msg-b"), ingress: "web"},
      extensions: %{contract_major: 1, project_id: project_b}
    }

    assert {:ok, %{status: :published}} = Pipeline.ingest(attrs_a)
    assert {:ok, %{status: :published}} = Pipeline.ingest(attrs_b)

    project_a_events = Pipeline.conversation_events(project_a, conversation_id)
    project_b_events = Pipeline.conversation_events(project_b, conversation_id)

    project_a_ids = Enum.map(project_a_events, & &1.id)
    project_b_ids = Enum.map(project_b_events, & &1.id)

    assert signal_id_a in project_a_ids
    assert signal_id_b in project_b_ids
    refute signal_id_b in project_a_ids
    refute signal_id_a in project_b_ids
  end

  test "cause_id links derived events for chain tracing" do
    conversation_id = unique_id("conversation")

    root_attrs = %{
      id: unique_id("root"),
      type: "conv.in.message.received",
      source: "/messaging/telegram",
      subject: conversation_id,
      data: %{message_id: unique_id("msg"), ingress: "telegram"},
      extensions: %{contract_major: 1}
    }

    child_attrs = %{
      id: unique_id("child"),
      type: "conv.effect.tool.execution.started",
      source: "/tool/runtime",
      subject: conversation_id,
      data: %{effect_id: unique_id("effect"), lifecycle: "started"},
      extensions: %{contract_major: 1}
    }

    assert {:ok, %{signal: root_signal}} = Pipeline.ingest(root_attrs)

    assert {:ok, %{signal: child_signal}} =
             Pipeline.ingest(child_attrs, cause_id: root_signal.id)

    chain = Pipeline.trace_chain(child_signal.id, :backward)
    chain_ids = Enum.map(chain, & &1.id)

    assert child_signal.id in chain_ids
    assert root_signal.id in chain_ids
  end

  test "invalid contract signals are rejected at ingress boundary" do
    invalid_attrs = %{
      type: "conv.in.message.received",
      source: "/messaging/web",
      data: %{message_id: unique_id("msg"), ingress: "web"},
      extensions: %{contract_major: 1}
    }

    assert {:error, {:contract_invalid, {:field, :subject, :missing}}} =
             Pipeline.ingest(invalid_attrs)
  end

  defp unique_id(prefix) do
    "#{prefix}-#{System.unique_integer([:positive, :monotonic])}"
  end
end
