defmodule Jido.Conversation.Runtime.Scheduler do
  @moduledoc """
  Deterministic scheduler for partition worker queues.

  Scheduling model:
  - Select only causally-ready events (`cause_id` already applied or absent)
  - Prioritize by explicit priority class (`P0`..`P3`)
  - Preserve stable ordering by queue sequence number within a priority class
  - Apply bounded fairness to avoid starvation of lower-priority ready events
  """

  alias Jido.Signal

  @type priority :: 0 | 1 | 2 | 3

  @type queue_entry :: %{
          seq: non_neg_integer(),
          signal: Signal.t(),
          priority: priority(),
          cause_id: String.t() | nil,
          subject: String.t(),
          enqueued_at_us: integer()
        }

  @type scheduler_state :: %{
          fairness_threshold: pos_integer(),
          last_priority: priority() | nil,
          consecutive_at_priority: non_neg_integer()
        }

  @type schedule_result ::
          {:ok, queue_entry(), [queue_entry()], scheduler_state()}
          | :none

  @terminal_suffixes [".completed", ".failed", ".error"]
  @transient_suffixes [".started", ".progress"]

  @spec initial_state(keyword()) :: scheduler_state()
  def initial_state(opts \\ []) do
    %{
      fairness_threshold: Keyword.get(opts, :fairness_threshold, 5),
      last_priority: nil,
      consecutive_at_priority: 0
    }
  end

  @spec make_entry(Signal.t(), non_neg_integer()) :: queue_entry()
  def make_entry(%Signal{} = signal, seq) when is_integer(seq) and seq >= 0 do
    %{
      seq: seq,
      signal: signal,
      priority: priority_for(signal.type),
      cause_id: cause_id(signal),
      subject: signal.subject || "default",
      enqueued_at_us: System.monotonic_time(:microsecond)
    }
  end

  @spec schedule([queue_entry()], scheduler_state(), MapSet.t(String.t())) :: schedule_result()
  def schedule(queue_entries, scheduler_state, applied_signal_ids)
      when is_list(queue_entries) and is_map(scheduler_state) do
    ready_entries =
      Enum.filter(queue_entries, fn entry ->
        causal_ready?(entry, applied_signal_ids)
      end)

    case ready_entries do
      [] ->
        :none

      _ ->
        priorities =
          ready_entries
          |> Enum.map(& &1.priority)
          |> Enum.uniq()
          |> Enum.sort()

        selected_priority = choose_priority(priorities, scheduler_state)

        selected =
          ready_entries
          |> Enum.filter(&(&1.priority == selected_priority))
          |> Enum.min_by(& &1.seq)

        remaining = List.delete(queue_entries, selected)
        next_state = update_scheduler_state(scheduler_state, selected_priority)

        {:ok, selected, remaining, next_state}
    end
  end

  @spec priority_for(String.t()) :: priority()
  def priority_for("conv.in.control.abort_requested"), do: 0
  def priority_for("conv.in.control.stop_requested"), do: 0
  def priority_for("conv.in.control.cancel_requested"), do: 0
  def priority_for(<<"conv.in.message", _::binary>>), do: 1
  def priority_for(<<"conv.out.", _::binary>>), do: 3

  def priority_for(type) when is_binary(type) do
    cond do
      ends_with_any?(type, @terminal_suffixes) -> 1
      ends_with_any?(type, @transient_suffixes) -> 2
      true -> 2
    end
  end

  defp choose_priority([only_priority], _scheduler_state), do: only_priority

  defp choose_priority(priorities, scheduler_state) do
    last_priority = scheduler_state.last_priority
    threshold = scheduler_state.fairness_threshold
    consecutive = scheduler_state.consecutive_at_priority

    cond do
      is_nil(last_priority) ->
        hd(priorities)

      consecutive < threshold ->
        hd(priorities)

      true ->
        starvation_escape_priority(priorities, last_priority)
    end
  end

  defp starvation_escape_priority(priorities, last_priority) do
    case Enum.find(priorities, &(&1 > last_priority)) do
      nil -> hd(priorities)
      priority -> priority
    end
  end

  defp update_scheduler_state(scheduler_state, selected_priority) do
    if scheduler_state.last_priority == selected_priority do
      %{scheduler_state | consecutive_at_priority: scheduler_state.consecutive_at_priority + 1}
    else
      %{scheduler_state | last_priority: selected_priority, consecutive_at_priority: 1}
    end
  end

  defp ends_with_any?(type, suffixes) do
    Enum.any?(suffixes, &String.ends_with?(type, &1))
  end

  defp cause_id(%Signal{} = signal) do
    extensions = signal.extensions || %{}
    data = signal.data || %{}

    Map.get(extensions, "cause_id") ||
      Map.get(extensions, :cause_id) ||
      Map.get(data, "cause_id") ||
      Map.get(data, :cause_id)
  end

  defp causal_ready?(%{cause_id: nil}, _applied_signal_ids), do: true

  defp causal_ready?(%{cause_id: cause_id}, applied_signal_ids) when is_binary(cause_id) do
    MapSet.member?(applied_signal_ids, cause_id)
  end

  defp causal_ready?(_entry, _applied_signal_ids), do: false
end
