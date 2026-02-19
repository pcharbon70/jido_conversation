defmodule JidoConversation.Runtime.SchedulerTest do
  use ExUnit.Case, async: true

  alias Jido.Signal
  alias JidoConversation.Runtime.Scheduler

  test "priority classification matches control/data plane model" do
    assert Scheduler.priority_for("conv.in.control.abort_requested") == 0
    assert Scheduler.priority_for("conv.in.message.received") == 1
    assert Scheduler.priority_for("conv.effect.tool.execution.completed") == 1
    assert Scheduler.priority_for("conv.effect.tool.execution.started") == 2
    assert Scheduler.priority_for("conv.out.assistant.delta") == 3
    assert Scheduler.priority_for("conv.unknown.anything") == 2
  end

  test "schedule returns causally-ready event first" do
    root = signal!("root-1", "conv.in.message.received", %{message_id: "m1", ingress: "test"})

    child =
      signal!(
        "child-1",
        "conv.effect.tool.execution.started",
        %{effect_id: "e1", lifecycle: "started"},
        extensions: %{"cause_id" => "root-1"}
      )

    queue = [Scheduler.make_entry(child, 0), Scheduler.make_entry(root, 1)]

    assert {:ok, selected, remaining, _next_state} =
             Scheduler.schedule(queue, Scheduler.initial_state(), MapSet.new())

    assert selected.signal.id == "root-1"
    assert length(remaining) == 1
  end

  test "schedule preserves sequence order within same priority" do
    signal_a = signal!("a-1", "conv.in.message.received", %{message_id: "m1", ingress: "test"})
    signal_b = signal!("b-1", "conv.in.message.received", %{message_id: "m2", ingress: "test"})

    queue = [Scheduler.make_entry(signal_b, 2), Scheduler.make_entry(signal_a, 1)]

    assert {:ok, selected, _, _} =
             Scheduler.schedule(queue, Scheduler.initial_state(), MapSet.new())

    assert selected.seq == 1
    assert selected.signal.id == "a-1"
  end

  test "fairness threshold allows lower-priority ready event to run" do
    high =
      signal!("h-1", "conv.in.control.abort_requested", %{message_id: "m1", ingress: "control"})

    lower = signal!("l-1", "conv.in.message.received", %{message_id: "m2", ingress: "test"})

    queue = [Scheduler.make_entry(high, 0), Scheduler.make_entry(lower, 1)]

    scheduler_state = %{
      Scheduler.initial_state(fairness_threshold: 2)
      | last_priority: 0,
        consecutive_at_priority: 2
    }

    assert {:ok, selected, _remaining, _next_state} =
             Scheduler.schedule(queue, scheduler_state, MapSet.new())

    assert selected.signal.id == "l-1"
    assert selected.priority == 1
  end

  defp signal!(id, type, data, opts \\ []) do
    source = Keyword.get(opts, :source, "/tests/scheduler")
    subject = Keyword.get(opts, :subject, "conversation-scheduler")
    extensions = Keyword.get(opts, :extensions, %{"contract_major" => 1})

    Signal.new!(type, data,
      id: id,
      source: source,
      subject: subject,
      extensions: extensions
    )
  end
end
