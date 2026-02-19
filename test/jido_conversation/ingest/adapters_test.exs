defmodule JidoConversation.Ingest.AdaptersTest do
  use ExUnit.Case, async: false

  alias JidoConversation.Ingest.Adapters.Control
  alias JidoConversation.Ingest.Adapters.Llm
  alias JidoConversation.Ingest.Adapters.Messaging
  alias JidoConversation.Ingest.Adapters.Timer
  alias JidoConversation.Ingest.Adapters.Tool
  alias JidoConversation.Ingest.Pipeline

  test "messaging adapter ingests conv.in message event" do
    conversation_id = unique_id("conversation")

    assert {:ok, %{status: :published, signal: signal}} =
             Messaging.ingest_received(
               conversation_id,
               unique_id("msg"),
               "slack",
               %{text: "hello world"}
             )

    assert signal.type == "conv.in.message.received"

    conversation_events = Pipeline.conversation_events(conversation_id)
    assert Enum.any?(conversation_events, &(&1.id == signal.id))
  end

  test "tool and llm adapters can preserve causal linkage" do
    conversation_id = unique_id("conversation")

    assert {:ok, %{signal: tool_signal}} =
             Tool.ingest_lifecycle(
               conversation_id,
               unique_id("effect"),
               "started",
               %{tool_name: "read_file"}
             )

    assert {:ok, %{signal: llm_signal}} =
             Llm.ingest_lifecycle(
               conversation_id,
               unique_id("effect"),
               "started",
               %{provider: "provider_x"},
               cause_id: tool_signal.id
             )

    chain = Pipeline.trace_chain(llm_signal.id, :backward)
    assert Enum.any?(chain, &(&1.id == tool_signal.id))
  end

  test "control and timer adapters ingest control-plane and time events" do
    conversation_id = unique_id("conversation")

    assert {:ok, %{signal: control_signal}} =
             Control.ingest_abort(conversation_id, unique_id("abort"), %{reason: "user_stop"})

    assert {:ok, %{signal: timer_signal}} =
             Timer.ingest_tick(conversation_id, unique_id("tick"), %{window_ms: 500})

    assert control_signal.type == "conv.in.control.abort_requested"
    assert timer_signal.type == "conv.in.timer.tick"

    conversation_events = Pipeline.conversation_events(conversation_id)
    event_ids = Enum.map(conversation_events, & &1.id)

    assert control_signal.id in event_ids
    assert timer_signal.id in event_ids
  end

  defp unique_id(prefix) do
    "#{prefix}-#{System.unique_integer([:positive, :monotonic])}"
  end
end
