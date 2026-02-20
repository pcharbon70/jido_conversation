defmodule JidoConversation.DeterminismTest do
  use ExUnit.Case, async: false

  alias JidoConversation.Config
  alias JidoConversation.Ingest
  alias JidoConversation.Ingest.Adapters.Messaging
  alias JidoConversation.Ingest.Adapters.Outbound
  alias JidoConversation.Projections
  alias JidoConversation.Projections.LlmContext
  alias JidoConversation.Projections.Timeline
  alias JidoConversation.Runtime.Coordinator
  alias JidoConversation.Runtime.EffectManager
  alias JidoConversation.Runtime.IngressSubscriber
  alias JidoConversation.Runtime.PartitionWorker
  alias JidoConversation.Runtime.Reducer
  alias JidoConversation.Runtime.Scheduler

  setup do
    wait_for_ingress_subscriber!()
    wait_for_runtime_idle!()
    :ok
  end

  test "replayed stream reproduces live reducer state for sampled conversation" do
    conversation_id = unique_id("conversation")
    effect_id = unique_id("effect")
    root_id = unique_id("root")
    progress_id = unique_id("progress")
    completed_id = unique_id("completed")

    assert {:ok, _} =
             Ingest.ingest(%{
               id: completed_id,
               type: "conv.effect.tool.execution.completed",
               source: "/tests/determinism",
               subject: conversation_id,
               data: %{effect_id: effect_id, lifecycle: "completed"},
               extensions: %{"contract_major" => 1, "cause_id" => root_id}
             })

    assert {:ok, _} =
             Ingest.ingest(%{
               id: progress_id,
               type: "conv.effect.tool.execution.progress",
               source: "/tests/determinism",
               subject: conversation_id,
               data: %{effect_id: effect_id, lifecycle: "progress"},
               extensions: %{"contract_major" => 1, "cause_id" => root_id}
             })

    assert {:ok, _} =
             Ingest.ingest(%{
               id: root_id,
               type: "conv.effect.tool.execution.started",
               source: "/tests/determinism",
               subject: conversation_id,
               data: %{effect_id: effect_id, lifecycle: "started"},
               extensions: %{"contract_major" => 1}
             })

    wait_for_runtime_idle!()

    partition_id =
      Coordinator.partition_for_subject(conversation_id, Config.runtime_partitions())

    live_conversation =
      eventually(fn ->
        snapshot = PartitionWorker.snapshot(partition_id)

        case Map.get(snapshot.conversations, conversation_id) do
          %{applied_count: applied_count} = conversation when applied_count > 0 ->
            {:ok, conversation}

          _other ->
            :retry
        end
      end)

    replayed_signals =
      eventually(fn ->
        signals =
          Ingest.conversation_events(conversation_id)
          |> Enum.filter(&runtime_replayable?/1)
          |> Enum.uniq_by(& &1.id)

        signal_ids = MapSet.new(Enum.map(signals, & &1.id))
        required_signal_ids = MapSet.new([root_id, progress_id, completed_id])

        if MapSet.subset?(required_signal_ids, signal_ids) do
          {:ok, signals}
        else
          :retry
        end
      end)

    replayed_state = replay_reducer_state(conversation_id, partition_id, replayed_signals)

    assert live_conversation.applied_count == replayed_state.applied_count
    assert live_conversation.stream_counts == replayed_state.stream_counts
    assert live_conversation.flags == replayed_state.flags
    assert live_conversation.in_flight_effects == replayed_state.in_flight_effects

    assert compact_event(live_conversation.last_event) == compact_event(replayed_state.last_event)

    assert compact_history(live_conversation.history) ==
             compact_history(Enum.reverse(replayed_state.history))
  end

  test "timeline and llm context projections match replay reconstruction" do
    conversation_id = unique_id("conversation")
    output_id = unique_id("output")

    assert {:ok, _} =
             Messaging.ingest_received(
               conversation_id,
               unique_id("msg"),
               "determinism",
               %{text: "hello determinism"}
             )

    assert {:ok, _} =
             Outbound.emit_assistant_delta(
               conversation_id,
               output_id,
               "web",
               "hi "
             )

    assert {:ok, _} =
             Outbound.emit_assistant_delta(
               conversation_id,
               output_id,
               "web",
               "there"
             )

    assert {:ok, _} =
             Outbound.emit_assistant_completed(
               conversation_id,
               output_id,
               "web",
               "hi there"
             )

    assert {:ok, _} =
             Outbound.emit_tool_status(
               conversation_id,
               unique_id("tool-output"),
               "web",
               "completed",
               %{message: "tool done"}
             )

    wait_for_runtime_idle!()

    live_timeline = Projections.timeline(conversation_id)
    live_context = Projections.llm_context(conversation_id)

    replayed_signals =
      eventually(fn ->
        signals = Ingest.conversation_events(conversation_id)
        if signals == [], do: :retry, else: {:ok, signals}
      end)

    replay_timeline = Timeline.from_events(replayed_signals)
    replay_context = LlmContext.from_events(replayed_signals)

    assert live_timeline == replay_timeline
    assert live_context == replay_context
  end

  defp replay_reducer_state(conversation_id, partition_id, signals) when is_list(signals) do
    queue_entries =
      signals
      |> Enum.with_index()
      |> Enum.map(fn {signal, seq} -> Scheduler.make_entry(signal, seq) end)

    drain_replay(
      queue_entries,
      Scheduler.initial_state(),
      MapSet.new(),
      Reducer.new(conversation_id),
      partition_id
    )
  end

  defp drain_replay(queue_entries, scheduler_state, applied_ids, reducer_state, partition_id) do
    case Scheduler.schedule(queue_entries, scheduler_state, applied_ids) do
      :none ->
        reducer_state

      {:ok, entry, remaining, next_scheduler_state} ->
        {:ok, next_reducer_state, _directives} =
          Reducer.apply_event(reducer_state, entry.signal,
            priority: entry.priority,
            partition_id: partition_id,
            scheduler_seq: entry.seq
          )

        drain_replay(
          remaining,
          next_scheduler_state,
          MapSet.put(applied_ids, entry.signal.id),
          next_reducer_state,
          partition_id
        )
    end
  end

  defp compact_history(history) when is_list(history), do: Enum.map(history, &compact_event/1)

  defp compact_event(nil), do: nil

  defp compact_event(event) when is_map(event) do
    %{
      id: Map.get(event, :id),
      type: Map.get(event, :type),
      priority: Map.get(event, :priority)
    }
  end

  defp runtime_replayable?(%{type: <<"conv.applied.", _::binary>>}), do: false
  defp runtime_replayable?(_signal), do: true

  defp unique_id(prefix) do
    "#{prefix}-#{System.unique_integer([:positive, :monotonic])}"
  end

  defp eventually(fun, attempts \\ 200)

  defp eventually(_fun, 0), do: raise("condition not met within timeout")

  defp eventually(fun, attempts) do
    case fun.() do
      {:ok, result} ->
        result

      :retry ->
        Process.sleep(20)
        eventually(fun, attempts - 1)
    end
  end

  defp wait_for_ingress_subscriber! do
    eventually(fn ->
      case :sys.get_state(IngressSubscriber) do
        %{subscription_id: subscription_id} when is_binary(subscription_id) ->
          {:ok, :ready}

        _other ->
          :retry
      end
    end)
  end

  defp wait_for_runtime_idle! do
    eventually(fn ->
      stats = Coordinator.stats()
      effect_stats = EffectManager.stats()

      busy? =
        stats.partitions
        |> Map.values()
        |> Enum.any?(fn partition -> partition.queue_size > 0 end)

      if busy? or effect_stats.in_flight_count > 0 do
        :retry
      else
        {:ok, :ready}
      end
    end)
  end
end
