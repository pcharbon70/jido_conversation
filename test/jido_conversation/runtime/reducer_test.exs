defmodule JidoConversation.Runtime.ReducerTest do
  use ExUnit.Case, async: true

  alias Jido.Signal
  alias JidoConversation.Runtime.Reducer

  test "message ingress emits applied marker and start_effect directives" do
    state = Reducer.new("conversation-reducer")

    signal =
      Signal.new!("conv.in.message.received", %{message_id: "m1", ingress: "test"},
        id: "sig-1",
        source: "/tests/reducer",
        subject: "conversation-reducer",
        extensions: %{"contract_major" => 1}
      )

    assert {:ok, new_state, directives} =
             Reducer.apply_event(state, signal, priority: 1, partition_id: 0, scheduler_seq: 10)

    assert new_state.applied_count == 1
    assert new_state.stream_counts[:in] == 1
    assert new_state.last_event.id == "sig-1"

    assert Enum.any?(directives, fn directive ->
             directive.type == :emit_applied_marker and
               directive.payload.applied_event_id == "sig-1" and
               directive.cause_id == "sig-1"
           end)

    assert Enum.any?(directives, fn directive ->
             directive.type == :start_effect and
               directive.payload.class == :llm and
               directive.payload.conversation_id == "conversation-reducer"
           end)
  end

  test "applied stream events do not emit nested applied directives" do
    state = Reducer.new("conversation-reducer")

    signal =
      Signal.new!("conv.applied.event.applied", %{applied_event_id: "base-1"},
        id: "applied-1",
        source: "/tests/reducer",
        subject: "conversation-reducer",
        extensions: %{"contract_major" => 1}
      )

    assert {:ok, new_state, directives} =
             Reducer.apply_event(state, signal, priority: 2, partition_id: 0, scheduler_seq: 1)

    assert new_state.applied_count == 1
    assert new_state.stream_counts[:applied] == 1
    assert directives == []
  end

  test "effect lifecycle transitions update in_flight_effects" do
    state = Reducer.new("conversation-reducer")

    started =
      Signal.new!(
        "conv.effect.tool.execution.started",
        %{effect_id: "eff-1", lifecycle: "started"},
        id: "eff-start",
        source: "/tests/reducer",
        subject: "conversation-reducer",
        extensions: %{"contract_major" => 1}
      )

    completed =
      Signal.new!(
        "conv.effect.tool.execution.completed",
        %{effect_id: "eff-1", lifecycle: "completed"},
        id: "eff-done",
        source: "/tests/reducer",
        subject: "conversation-reducer",
        extensions: %{"contract_major" => 1}
      )

    {:ok, state_after_start, _} =
      Reducer.apply_event(state, started, priority: 2, partition_id: 0, scheduler_seq: 1)

    assert state_after_start.in_flight_effects["eff-1"] == :started

    {:ok, state_after_done, _} =
      Reducer.apply_event(state_after_start, completed,
        priority: 1,
        partition_id: 0,
        scheduler_seq: 2
      )

    refute Map.has_key?(state_after_done.in_flight_effects, "eff-1")
  end

  test "abort control event sets abort flag and emits cancel directive" do
    state = Reducer.new("conversation-reducer")

    signal =
      Signal.new!("conv.in.control.abort_requested", %{message_id: "ctrl-1", ingress: "control"},
        id: "abort-1",
        source: "/tests/reducer",
        subject: "conversation-reducer",
        extensions: %{"contract_major" => 1}
      )

    {:ok, new_state, directives} =
      Reducer.apply_event(state, signal, priority: 0, partition_id: 0, scheduler_seq: 1)

    assert new_state.flags[:abort_requested] == true

    assert Enum.any?(directives, fn directive ->
             directive.type == :cancel_effects and
               directive.payload.conversation_id == "conversation-reducer" and
               directive.payload.reason == "conv.in.control.abort_requested"
           end)
  end
end
