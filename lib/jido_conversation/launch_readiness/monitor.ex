defmodule JidoConversation.LaunchReadiness.Monitor do
  @moduledoc """
  Periodically evaluates launch readiness and emits status/alert telemetry.
  """

  use GenServer

  require Logger

  alias JidoConversation.Config
  alias JidoConversation.Operations

  @snapshot_event [:jido_conversation, :launch_readiness, :snapshot]
  @alert_event [:jido_conversation, :launch_readiness, :alert]

  @type monitor_snapshot :: %{
          enabled?: boolean(),
          interval_ms: pos_integer(),
          max_queue_depth: non_neg_integer(),
          max_dispatch_failures: non_neg_integer(),
          total_checks: non_neg_integer(),
          total_alerts: non_neg_integer(),
          last_status: Operations.readiness_status() | nil,
          last_checked_at: DateTime.t() | nil,
          last_alert_at: DateTime.t() | nil,
          last_report: Operations.launch_readiness_report() | nil
        }

  @type state :: monitor_snapshot()

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec snapshot() :: monitor_snapshot()
  def snapshot do
    GenServer.call(__MODULE__, :snapshot)
  end

  @spec check_now() :: {:ok, Operations.launch_readiness_report()}
  def check_now do
    GenServer.call(__MODULE__, :check_now, 15_000)
  end

  @impl true
  def init(opts) do
    config =
      Config.launch_readiness_monitor()
      |> Keyword.merge(opts)

    state = %{
      enabled?: Keyword.fetch!(config, :enabled),
      interval_ms: Keyword.fetch!(config, :interval_ms),
      max_queue_depth: Keyword.fetch!(config, :max_queue_depth),
      max_dispatch_failures: Keyword.fetch!(config, :max_dispatch_failures),
      total_checks: 0,
      total_alerts: 0,
      last_status: nil,
      last_checked_at: nil,
      last_alert_at: nil,
      last_report: nil
    }

    if state.enabled? do
      :ok = schedule_next_check(state.interval_ms)
    end

    {:ok, state}
  end

  @impl true
  def handle_call(:snapshot, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_call(:check_now, _from, state) do
    {report, updated_state} = perform_check(state)
    {:reply, {:ok, report}, updated_state}
  end

  @impl true
  def handle_info(:run_check, state) do
    {_report, updated_state} = perform_check(state)

    if updated_state.enabled? do
      :ok = schedule_next_check(updated_state.interval_ms)
    end

    {:noreply, updated_state}
  end

  defp perform_check(state) do
    {:ok, report} =
      Operations.launch_readiness(
        max_queue_depth: state.max_queue_depth,
        max_dispatch_failures: state.max_dispatch_failures
      )

    critical_issue_count = Enum.count(report.issues, &(&1.severity == :critical))
    warning_issue_count = Enum.count(report.issues, &(&1.severity == :warning))

    :telemetry.execute(
      @snapshot_event,
      %{
        total_checks: state.total_checks + 1,
        issue_count: length(report.issues),
        timestamp_ms: DateTime.to_unix(report.checked_at, :millisecond)
      },
      %{
        status: report.status,
        critical_issue_count: critical_issue_count,
        warning_issue_count: warning_issue_count
      }
    )

    {alerted?, last_alert_at, total_alerts} =
      maybe_emit_not_ready_alert(
        state,
        report,
        critical_issue_count,
        warning_issue_count
      )

    updated_state = %{
      state
      | total_checks: state.total_checks + 1,
        total_alerts: total_alerts,
        last_status: report.status,
        last_checked_at: report.checked_at,
        last_alert_at: last_alert_at,
        last_report: report
    }

    if alerted? do
      Logger.warning(
        "launch readiness status transitioned to not_ready critical_issues=#{critical_issue_count} warning_issues=#{warning_issue_count}"
      )
    end

    {report, updated_state}
  end

  defp maybe_emit_not_ready_alert(state, report, critical_issue_count, warning_issue_count) do
    if report.status == :not_ready and state.last_status != :not_ready do
      next_alert_count = state.total_alerts + 1
      alert_time = report.checked_at

      :telemetry.execute(
        @alert_event,
        %{
          total_alerts: next_alert_count,
          timestamp_ms: DateTime.to_unix(alert_time, :millisecond)
        },
        %{
          status: report.status,
          critical_issue_count: critical_issue_count,
          warning_issue_count: warning_issue_count
        }
      )

      {true, alert_time, next_alert_count}
    else
      {false, state.last_alert_at, state.total_alerts}
    end
  end

  defp schedule_next_check(interval_ms) do
    _timer_ref = Process.send_after(self(), :run_check, interval_ms)
    :ok
  end
end
