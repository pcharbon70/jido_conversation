defmodule JidoConversation.TelemetryTest do
  use ExUnit.Case, async: false

  alias JidoConversation.Telemetry

  setup do
    :ok = Telemetry.reset()
    :ok
  end

  test "aggregates runtime and dispatch metrics" do
    now = System.monotonic_time(:microsecond)
    readiness_timestamp_ms = System.system_time(:millisecond)
    partition_id = System.unique_integer([:positive, :monotonic]) + 1_000
    signal_id = "signal-#{System.unique_integer([:positive, :monotonic])}"
    baseline = Telemetry.snapshot()

    :telemetry.execute(
      [:jido_conversation, :runtime, :queue, :depth],
      %{depth: 3},
      %{partition_id: partition_id}
    )

    :telemetry.execute(
      [:jido_conversation, :runtime, :apply, :stop],
      %{duration_us: 1_750},
      %{partition_id: partition_id, signal_id: "signal-1"}
    )

    :telemetry.execute(
      [:jido_conversation, :runtime, :abort, :latency],
      %{duration_us: 2_500},
      %{partition_id: partition_id, signal_id: "signal-2"}
    )

    :telemetry.execute(
      [:jido, :signal, :subscription, :dispatch, :retry],
      %{attempt: 1},
      %{subscription_id: "sub-1", signal_id: "signal-3"}
    )

    :telemetry.execute(
      [:jido, :signal, :subscription, :dlq],
      %{},
      %{subscription_id: "sub-1", signal_id: "signal-3"}
    )

    :telemetry.execute(
      [:jido, :signal, :bus, :dispatch_error],
      %{timestamp: now},
      %{
        bus_name: :jido_conversation_bus,
        signal_id: signal_id,
        signal_type: "conv.in.message.received",
        subscription_id: "sub-1",
        error: :test_error
      }
    )

    :telemetry.execute(
      [:jido_conversation, :launch_readiness, :snapshot],
      %{total_checks: 1, issue_count: 2, timestamp_ms: readiness_timestamp_ms},
      %{status: :warning, critical_issue_count: 0, warning_issue_count: 2}
    )

    :telemetry.execute(
      [:jido_conversation, :launch_readiness, :alert],
      %{total_alerts: 1, timestamp_ms: readiness_timestamp_ms},
      %{status: :not_ready, critical_issue_count: 1, warning_issue_count: 0}
    )

    snapshot =
      eventually(fn ->
        current = Telemetry.snapshot()

        if current.retry_count >= baseline.retry_count + 1 and
             current.dlq_count >= baseline.dlq_count + 1 and
             current.dispatch_failure_count >= baseline.dispatch_failure_count + 1 and
             current.apply_latency_ms.count >= baseline.apply_latency_ms.count + 1 and
             current.abort_latency_ms.count >= baseline.abort_latency_ms.count + 1 and
             current.launch_readiness.checks >= baseline.launch_readiness.checks + 1 and
             current.launch_readiness.alerts >= baseline.launch_readiness.alerts + 1 do
          {:ok, current}
        else
          :retry
        end
      end)

    assert snapshot.queue_depth.by_partition[partition_id] == 3
    assert snapshot.apply_latency_ms.count >= baseline.apply_latency_ms.count + 1
    assert snapshot.apply_latency_ms.avg_ms > 0.0
    assert snapshot.abort_latency_ms.count >= baseline.abort_latency_ms.count + 1
    assert snapshot.retry_count >= baseline.retry_count + 1
    assert snapshot.dlq_count >= baseline.dlq_count + 1
    assert snapshot.dispatch_failure_count >= baseline.dispatch_failure_count + 1
    assert is_map(snapshot.last_dispatch_failure)
    assert snapshot.launch_readiness.last_status == :warning
    assert is_integer(snapshot.launch_readiness.last_checked_at_ms)
    assert is_integer(snapshot.launch_readiness.last_alerted_at_ms)
  end

  test "reset clears metrics to baseline" do
    partition_id = System.unique_integer([:positive, :monotonic]) + 2_000

    :telemetry.execute(
      [:jido_conversation, :runtime, :queue, :depth],
      %{depth: 7},
      %{partition_id: partition_id}
    )

    _snapshot =
      eventually(fn ->
        current = Telemetry.snapshot()
        if current.queue_depth.by_partition[partition_id] == 7, do: {:ok, current}, else: :retry
      end)

    assert :ok = Telemetry.reset()

    reset_snapshot =
      eventually(fn ->
        current = Telemetry.snapshot()

        if Map.get(current.queue_depth.by_partition, partition_id, 0) == 0 do
          {:ok, current}
        else
          :retry
        end
      end)

    assert Map.get(reset_snapshot.queue_depth.by_partition, partition_id, 0) == 0
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
