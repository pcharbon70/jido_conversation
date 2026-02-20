defmodule JidoConversation.LaunchReadiness.MonitorTest do
  use ExUnit.Case, async: false

  alias JidoConversation.Config
  alias JidoConversation.LaunchReadiness.Monitor

  setup do
    {:ok, _report} = Monitor.check_now()
    :ok
  end

  test "check_now stores the latest report in snapshot state" do
    baseline = Monitor.snapshot()

    assert {:ok, report} = Monitor.check_now()

    snapshot =
      eventually(fn ->
        current = Monitor.snapshot()

        if current.total_checks >= baseline.total_checks + 1 do
          {:ok, current}
        else
          :retry
        end
      end)

    assert snapshot.last_report.status == report.status
    assert snapshot.last_status == report.status
    assert snapshot.total_checks >= 1
    assert snapshot.interval_ms > 0
  end

  test "check_now emits launch readiness snapshot telemetry" do
    handler_id = {:launch_readiness_monitor_snapshot_test, System.unique_integer([:positive])}
    parent = self()

    :ok =
      :telemetry.attach(
        handler_id,
        [:jido_conversation, :launch_readiness, :snapshot],
        fn _event, measurements, metadata, _config ->
          send(parent, {:launch_readiness_snapshot_telemetry, measurements, metadata})
        end,
        nil
      )

    on_exit(fn ->
      :telemetry.detach(handler_id)
    end)

    assert {:ok, _report} = Monitor.check_now()

    assert_receive {:launch_readiness_snapshot_telemetry, measurements, metadata}, 2_000
    assert measurements.total_checks >= 1
    assert measurements.issue_count >= 0
    assert metadata.status in [:ready, :warning, :not_ready]
  end

  test "transition to not_ready emits launch readiness alert telemetry" do
    current_cfg = Config.event_system()
    previous_bus_name = Keyword.fetch!(current_cfg, :bus_name)
    invalid_bus_name = :"#{previous_bus_name}_invalid"
    parent = self()
    handler_id = {:launch_readiness_monitor_alert_test, System.unique_integer([:positive])}

    :ok =
      :telemetry.attach(
        handler_id,
        [:jido_conversation, :launch_readiness, :alert],
        fn _event, measurements, metadata, _config ->
          send(parent, {:launch_readiness_alert_telemetry, measurements, metadata})
        end,
        nil
      )

    on_exit(fn ->
      :telemetry.detach(handler_id)

      restored_cfg = Keyword.put(current_cfg, :bus_name, previous_bus_name)
      Application.put_env(:jido_conversation, JidoConversation.EventSystem, restored_cfg)
      _ = Monitor.check_now()
    end)

    assert {:ok, baseline_report} = Monitor.check_now()
    refute baseline_report.status == :not_ready

    updated_cfg = Keyword.put(current_cfg, :bus_name, invalid_bus_name)
    Application.put_env(:jido_conversation, JidoConversation.EventSystem, updated_cfg)

    assert {:ok, report} = Monitor.check_now()
    assert report.status == :not_ready

    assert_receive {:launch_readiness_alert_telemetry, measurements, metadata}, 2_000
    assert measurements.total_alerts >= 1
    assert metadata.status == :not_ready

    snapshot = Monitor.snapshot()
    assert snapshot.total_alerts >= 1
    assert snapshot.last_status == :not_ready
  end

  defp eventually(fun, attempts \\ 100)

  defp eventually(_fun, 0), do: raise("condition not met within timeout")

  defp eventually(fun, attempts) do
    case fun.() do
      {:ok, result} ->
        result

      :retry ->
        Process.sleep(10)
        eventually(fun, attempts - 1)
    end
  end
end
