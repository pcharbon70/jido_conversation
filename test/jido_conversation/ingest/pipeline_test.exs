defmodule JidoConversation.Ingest.PipelineTest do
  use ExUnit.Case, async: false

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
    assert Enum.map(conversation_events, & &1.id) == [signal.id]

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
    assert length(conversation_events) == 1
    assert hd(conversation_events).id == signal_id
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
