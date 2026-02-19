defmodule JidoConversation.Runtime.PartitionWorker do
  @moduledoc """
  Per-partition runtime worker.

  This process keeps a deterministic queue, applies the scheduler to select the
  next event, runs pure reducer transitions, and executes emitted directives.
  """

  use GenServer

  require Logger

  alias Jido.Signal
  alias JidoConversation.Ingest
  alias JidoConversation.Runtime.EffectManager
  alias JidoConversation.Runtime.Reducer
  alias JidoConversation.Runtime.Scheduler

  @max_steps_per_drain 200

  @type state :: %{
          partition_id: non_neg_integer(),
          next_seq: non_neg_integer(),
          drain_scheduled?: boolean(),
          queue_entries: [Scheduler.queue_entry()],
          scheduler_state: Scheduler.scheduler_state(),
          applied_signal_ids: MapSet.t(String.t()),
          conversations: %{String.t() => Reducer.conversation_state()},
          processed_count: non_neg_integer(),
          emitted_applied_count: non_neg_integer(),
          last_applied: map() | nil
        }

  @spec start_link(non_neg_integer()) :: GenServer.on_start()
  def start_link(partition_id) when is_integer(partition_id) and partition_id >= 0 do
    GenServer.start_link(__MODULE__, partition_id, name: via_tuple(partition_id))
  end

  @spec enqueue(non_neg_integer(), Signal.t()) :: :ok
  def enqueue(partition_id, signal) do
    GenServer.cast(via_tuple(partition_id), {:enqueue, signal})
  end

  @spec stats(non_neg_integer()) :: map()
  def stats(partition_id) do
    GenServer.call(via_tuple(partition_id), :stats)
  end

  @spec snapshot(non_neg_integer()) :: map()
  def snapshot(partition_id) do
    GenServer.call(via_tuple(partition_id), :snapshot)
  end

  @impl true
  def init(partition_id) do
    {:ok,
     %{
       partition_id: partition_id,
       next_seq: 0,
       drain_scheduled?: false,
       queue_entries: [],
       scheduler_state: Scheduler.initial_state(),
       applied_signal_ids: MapSet.new(),
       conversations: %{},
       processed_count: 0,
       emitted_applied_count: 0,
       last_applied: nil
     }}
  end

  @impl true
  def handle_cast({:enqueue, signal}, state) do
    entry = Scheduler.make_entry(signal, state.next_seq)

    state =
      state
      |> Map.put(:next_seq, state.next_seq + 1)
      |> Map.put(:queue_entries, state.queue_entries ++ [entry])
      |> drain_and_schedule()

    {:noreply, state}
  end

  @impl true
  def handle_info(:continue_drain, state) do
    state =
      state
      |> Map.put(:drain_scheduled?, false)
      |> drain_and_schedule()

    {:noreply, state}
  end

  @impl true
  def handle_call(:stats, _from, state) do
    {:reply,
     %{
       partition_id: state.partition_id,
       queue_size: length(state.queue_entries),
       processed_count: state.processed_count,
       emitted_applied_count: state.emitted_applied_count,
       tracked_conversations: map_size(state.conversations),
       last_applied: state.last_applied
     }, state}
  end

  @impl true
  def handle_call(:snapshot, _from, state) do
    conversations =
      Enum.into(state.conversations, %{}, fn {conversation_id, conversation_state} ->
        {conversation_id,
         %{
           applied_count: conversation_state.applied_count,
           flags: conversation_state.flags,
           in_flight_effects: conversation_state.in_flight_effects,
           last_event: conversation_state.last_event,
           stream_counts: conversation_state.stream_counts,
           history: Enum.reverse(conversation_state.history)
         }}
      end)

    snapshot = %{
      partition_id: state.partition_id,
      queue_size: length(state.queue_entries),
      processed_count: state.processed_count,
      emitted_applied_count: state.emitted_applied_count,
      applied_signal_count: MapSet.size(state.applied_signal_ids),
      last_applied: state.last_applied,
      conversations: conversations
    }

    {:reply, snapshot, state}
  end

  @spec via_tuple(non_neg_integer()) :: {:via, Registry, {module(), tuple()}}
  def via_tuple(partition_id) do
    {:via, Registry, {JidoConversation.Runtime.Registry, {:partition, partition_id}}}
  end

  defp drain_and_schedule(state) do
    {state, steps} = drain_queue(state)

    if steps >= @max_steps_per_drain and state.queue_entries != [] do
      schedule_continue_drain(state)
    else
      Map.put(state, :drain_scheduled?, false)
    end
  end

  defp schedule_continue_drain(%{drain_scheduled?: true} = state), do: state

  defp schedule_continue_drain(state) do
    Process.send(self(), :continue_drain, [])
    Map.put(state, :drain_scheduled?, true)
  end

  defp drain_queue(state), do: drain_queue(state, 0)

  defp drain_queue(state, steps) when steps >= @max_steps_per_drain, do: {state, steps}

  defp drain_queue(state, steps) do
    case Scheduler.schedule(state.queue_entries, state.scheduler_state, state.applied_signal_ids) do
      :none ->
        {state, steps}

      {:ok, entry, remaining_entries, scheduler_state} ->
        state =
          state
          |> Map.put(:queue_entries, remaining_entries)
          |> Map.put(:scheduler_state, scheduler_state)
          |> apply_entry(entry)

        drain_queue(state, steps + 1)
    end
  end

  defp apply_entry(state, entry) do
    conversation_id = entry.subject

    conversation_state =
      Map.get_lazy(state.conversations, conversation_id, fn ->
        Reducer.new(conversation_id)
      end)

    {:ok, updated_conversation, directives} =
      Reducer.apply_event(conversation_state, entry.signal,
        priority: entry.priority,
        partition_id: state.partition_id,
        scheduler_seq: entry.seq
      )

    emitted_count = execute_directives(directives)

    %{
      state
      | conversations: Map.put(state.conversations, conversation_id, updated_conversation),
        applied_signal_ids: MapSet.put(state.applied_signal_ids, entry.signal.id),
        processed_count: state.processed_count + 1,
        emitted_applied_count: state.emitted_applied_count + emitted_count,
        last_applied: %{
          signal_id: entry.signal.id,
          type: entry.signal.type,
          priority: entry.priority,
          seq: entry.seq,
          conversation_id: conversation_id
        }
    }
  end

  defp execute_directives(directives) when is_list(directives) do
    Enum.reduce(directives, 0, fn directive, emitted ->
      emitted + execute_directive(directive)
    end)
  end

  defp execute_directive(%{type: :emit_applied_marker, payload: payload, cause_id: cause_id}) do
    attrs = %{
      type: "conv.applied.event.applied",
      source: "/runtime/reducer",
      subject: payload.subject,
      data: %{
        applied_event_id: payload.applied_event_id,
        original_type: payload.original_type,
        priority: payload.priority,
        partition_id: payload.partition_id,
        scheduler_seq: payload.scheduler_seq
      },
      extensions: %{"contract_major" => 1, "cause_id" => cause_id}
    }

    case Ingest.ingest(attrs, cause_id: cause_id) do
      {:ok, _result} ->
        1

      {:error, reason} ->
        Logger.warning(
          "failed to emit applied marker for #{payload.applied_event_id}: #{inspect(reason)}"
        )

        0
    end
  end

  defp execute_directive(%{type: :start_effect, payload: payload, cause_id: cause_id}) do
    EffectManager.start_effect(payload, cause_id)
    0
  end

  defp execute_directive(%{type: :cancel_effects, payload: payload, cause_id: cause_id}) do
    conversation_id = payload.conversation_id || payload["conversation_id"]
    reason = payload.reason || payload["reason"] || "cancel_requested"

    if is_binary(conversation_id) and is_binary(reason) do
      EffectManager.cancel_conversation(conversation_id, reason, cause_id)
    end

    0
  end

  defp execute_directive(_directive), do: 0
end
