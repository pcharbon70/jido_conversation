defmodule Jido.Conversation.Runtime.Coordinator do
  @moduledoc """
  Routes incoming signals to partition workers.
  """

  use GenServer

  require Logger

  alias Jido.Conversation.Config
  alias Jido.Conversation.Runtime.PartitionWorker

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec enqueue(Jido.Signal.t()) :: :ok
  def enqueue(signal) do
    GenServer.cast(__MODULE__, {:enqueue, signal})
  end

  @spec stats() :: map()
  def stats do
    GenServer.call(__MODULE__, :stats)
  end

  @spec partition_for_subject(String.t() | nil, pos_integer()) :: non_neg_integer()
  def partition_for_subject(subject, partition_count)
      when is_integer(partition_count) and partition_count > 0 do
    :erlang.phash2(subject || "default", partition_count)
  end

  @impl true
  def init(_opts) do
    partition_count = Config.runtime_partitions()

    Enum.each(0..(partition_count - 1), fn partition_id ->
      DynamicSupervisor.start_child(
        Jido.Conversation.Runtime.PartitionSupervisor,
        {PartitionWorker, partition_id}
      )
    end)

    {:ok, %{partition_count: partition_count}}
  end

  @impl true
  def handle_cast({:enqueue, signal}, state) do
    partition_id = partition_for_subject(Map.get(signal, :subject), state.partition_count)

    try do
      PartitionWorker.enqueue(partition_id, signal)
    catch
      :exit, reason ->
        Logger.warning("failed to route signal to partition=#{partition_id}: #{inspect(reason)}")
    end

    {:noreply, state}
  end

  @impl true
  def handle_call(:stats, _from, state) do
    partitions =
      Enum.reduce(0..(state.partition_count - 1), %{}, fn partition_id, acc ->
        Map.put(acc, partition_id, PartitionWorker.stats(partition_id))
      end)

    {:reply, %{partition_count: state.partition_count, partitions: partitions}, state}
  end
end
