defmodule JidoConversation.Runtime.PartitionWorker do
  @moduledoc """
  Per-partition event worker skeleton.

  In phase 1 this only tracks queue counters and last seen metadata.
  Reducer/scheduler logic is implemented in later phases.
  """

  use GenServer

  @type state :: %{
          partition_id: non_neg_integer(),
          handled_count: non_neg_integer(),
          last_signal_id: String.t() | nil,
          last_signal_type: String.t() | nil
        }

  @spec start_link(non_neg_integer()) :: GenServer.on_start()
  def start_link(partition_id) when is_integer(partition_id) and partition_id >= 0 do
    GenServer.start_link(__MODULE__, partition_id, name: via_tuple(partition_id))
  end

  @spec enqueue(non_neg_integer(), Jido.Signal.t()) :: :ok
  def enqueue(partition_id, signal) do
    GenServer.cast(via_tuple(partition_id), {:enqueue, signal})
  end

  @spec stats(non_neg_integer()) :: map()
  def stats(partition_id) do
    GenServer.call(via_tuple(partition_id), :stats)
  end

  @impl true
  def init(partition_id) do
    {:ok,
     %{partition_id: partition_id, handled_count: 0, last_signal_id: nil, last_signal_type: nil}}
  end

  @impl true
  def handle_cast({:enqueue, signal}, state) do
    {:noreply,
     %{
       state
       | handled_count: state.handled_count + 1,
         last_signal_id: Map.get(signal, :id),
         last_signal_type: Map.get(signal, :type)
     }}
  end

  @impl true
  def handle_call(:stats, _from, state) do
    {:reply, state, state}
  end

  @spec via_tuple(non_neg_integer()) :: {:via, Registry, {module(), tuple()}}
  def via_tuple(partition_id) do
    {:via, Registry, {JidoConversation.Runtime.Registry, {:partition, partition_id}}}
  end
end
