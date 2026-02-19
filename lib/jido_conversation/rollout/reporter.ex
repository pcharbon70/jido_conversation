defmodule JidoConversation.Rollout.Reporter do
  @moduledoc """
  Aggregates rollout decisions and parity reports for migration visibility.
  """

  use GenServer

  alias Jido.Signal
  alias JidoConversation.Config
  alias JidoConversation.Rollout

  @type snapshot :: %{
          decision_counts: %{Rollout.action() => non_neg_integer()},
          reason_counts: %{atom() => non_neg_integer()},
          parity_sample_count: non_neg_integer(),
          parity_report_count: non_neg_integer(),
          parity_status_counts: %{
            JidoConversation.Rollout.Parity.parity_status() => non_neg_integer()
          },
          recent_parity_samples: [map()],
          recent_parity_reports: [map()]
        }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec record_decision(Rollout.decision()) :: :ok
  def record_decision(decision) when is_map(decision) do
    GenServer.cast(__MODULE__, {:record_decision, decision})
  end

  @spec record_parity_sample(Signal.t(), Rollout.decision()) :: :ok
  def record_parity_sample(%Signal{} = signal, decision) when is_map(decision) do
    GenServer.cast(__MODULE__, {:record_parity_sample, signal, decision})
  end

  @spec record_parity_report(map()) :: :ok
  def record_parity_report(report) when is_map(report) do
    GenServer.cast(__MODULE__, {:record_parity_report, report})
  end

  @spec snapshot() :: snapshot()
  def snapshot do
    GenServer.call(__MODULE__, :snapshot)
  end

  @spec reset() :: :ok
  def reset do
    GenServer.call(__MODULE__, :reset)
  end

  @impl true
  def init(_opts) do
    max_reports =
      Config.rollout_parity()
      |> Keyword.get(:max_reports, 200)

    {:ok, new_state(max_reports)}
  end

  @impl true
  def handle_cast({:record_decision, decision}, state) do
    action = Map.get(decision, :action, :drop)
    reason = Map.get(decision, :reason, :unknown)

    decision_counts = Map.update(state.decision_counts, action, 1, &(&1 + 1))
    reason_counts = Map.update(state.reason_counts, reason, 1, &(&1 + 1))

    {:noreply, %{state | decision_counts: decision_counts, reason_counts: reason_counts}}
  end

  def handle_cast({:record_parity_sample, %Signal{} = signal, decision}, state) do
    sample = %{
      signal_id: signal.id,
      type: signal.type,
      subject: signal.subject,
      sampled_at: DateTime.utc_now(),
      mode: Map.get(decision, :mode),
      action: Map.get(decision, :action),
      reason: Map.get(decision, :reason)
    }

    {:noreply,
     %{
       state
       | parity_sample_count: state.parity_sample_count + 1,
         recent_parity_samples:
           bounded_prepend(state.recent_parity_samples, sample, state.max_reports)
     }}
  end

  def handle_cast({:record_parity_report, report}, state) do
    status = Map.get(report, :status) || Map.get(report, "status")
    parity_status_counts = increment_parity_status(state.parity_status_counts, status)

    {:noreply,
     %{
       state
       | parity_report_count: state.parity_report_count + 1,
         parity_status_counts: parity_status_counts,
         recent_parity_reports:
           bounded_prepend(state.recent_parity_reports, report, state.max_reports)
     }}
  end

  @impl true
  def handle_call(:snapshot, _from, state) do
    snapshot = %{
      decision_counts: state.decision_counts,
      reason_counts: state.reason_counts,
      parity_sample_count: state.parity_sample_count,
      parity_report_count: state.parity_report_count,
      parity_status_counts: state.parity_status_counts,
      recent_parity_samples: state.recent_parity_samples,
      recent_parity_reports: state.recent_parity_reports
    }

    {:reply, snapshot, state}
  end

  def handle_call(:reset, _from, state) do
    {:reply, :ok, new_state(state.max_reports)}
  end

  defp new_state(max_reports) do
    %{
      max_reports: max_reports,
      decision_counts: %{
        enqueue_runtime: 0,
        parity_only: 0,
        drop: 0
      },
      reason_counts: %{},
      parity_sample_count: 0,
      parity_report_count: 0,
      parity_status_counts: %{
        match: 0,
        mismatch: 0,
        legacy_unavailable: 0
      },
      recent_parity_samples: [],
      recent_parity_reports: []
    }
  end

  defp bounded_prepend(list, entry, max_reports) when is_list(list) do
    [entry | list]
    |> Enum.take(max_reports)
  end

  defp increment_parity_status(counts, status)
       when status in [:match, :mismatch, :legacy_unavailable] do
    Map.update(counts, status, 1, &(&1 + 1))
  end

  defp increment_parity_status(counts, _status), do: counts
end
