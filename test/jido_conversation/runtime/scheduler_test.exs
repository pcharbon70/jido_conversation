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

  test "burst traffic applies ready lower-priority events at bounded intervals" do
    fairness_threshold = 5
    high_count = 40
    lower_count = 4

    high_entries =
      for seq <- 0..(high_count - 1) do
        signal =
          signal!(
            "burst-h-#{seq}",
            "conv.in.control.abort_requested",
            %{message_id: "mh-#{seq}", ingress: "control"}
          )

        Scheduler.make_entry(signal, seq)
      end

    lower_entries =
      for offset <- 0..(lower_count - 1) do
        seq = high_count + offset

        signal =
          signal!(
            "burst-l-#{offset}",
            "conv.in.message.received",
            %{message_id: "ml-#{offset}", ingress: "test"}
          )

        Scheduler.make_entry(signal, seq)
      end

    scheduled =
      high_entries
      |> Kernel.++(lower_entries)
      |> drain_schedule(Scheduler.initial_state(fairness_threshold: fairness_threshold))

    lower_positions =
      scheduled
      |> Enum.with_index(1)
      |> Enum.filter(fn {entry, _index} -> entry.priority == 1 end)
      |> Enum.map(fn {_entry, index} -> index end)

    expected_positions =
      Enum.map(1..lower_count, fn occurrence ->
        occurrence * (fairness_threshold + 1)
      end)

    assert length(scheduled) == high_count + lower_count
    assert lower_positions == expected_positions
  end

  test "burst queue does not let lower-priority events wait behind full high-priority backlog" do
    fairness_threshold = 5
    high_count = 240

    high_entries =
      for seq <- 0..(high_count - 1) do
        signal =
          signal!(
            "load-h-#{seq}",
            "conv.in.control.abort_requested",
            %{message_id: "mh-#{seq}", ingress: "control"}
          )

        Scheduler.make_entry(signal, seq)
      end

    lower_entry =
      signal!(
        "load-l-1",
        "conv.in.message.received",
        %{message_id: "ml-1", ingress: "test"}
      )
      |> Scheduler.make_entry(high_count)

    scheduled =
      high_entries
      |> Kernel.++([lower_entry])
      |> drain_schedule(Scheduler.initial_state(fairness_threshold: fairness_threshold))

    lower_position =
      scheduled
      |> Enum.with_index(1)
      |> Enum.find_value(fn {entry, index} ->
        if entry.signal.id == "load-l-1", do: index
      end)

    assert lower_position == fairness_threshold + 1
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

  defp drain_schedule(entries, scheduler_state, applied_signal_ids \\ MapSet.new(), acc \\ [])

  defp drain_schedule([], _scheduler_state, _applied_signal_ids, acc), do: Enum.reverse(acc)

  defp drain_schedule(entries, scheduler_state, applied_signal_ids, acc) do
    case Scheduler.schedule(entries, scheduler_state, applied_signal_ids) do
      :none ->
        Enum.reverse(acc)

      {:ok, selected, remaining, next_scheduler_state} ->
        next_applied_ids = MapSet.put(applied_signal_ids, selected.signal.id)

        drain_schedule(remaining, next_scheduler_state, next_applied_ids, [selected | acc])
    end
  end
end
