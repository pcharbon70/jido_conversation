defmodule JidoConversation.TelemetryTest do
  use ExUnit.Case, async: false

  alias JidoConversation.Telemetry

  setup do
    :ok = Telemetry.reset()
    :ok
  end

  test "aggregates runtime and dispatch metrics" do
    now = System.monotonic_time(:microsecond)

    :telemetry.execute(
      [:jido_conversation, :runtime, :queue, :depth],
      %{depth: 3},
      %{partition_id: 1}
    )

    :telemetry.execute(
      [:jido_conversation, :runtime, :apply, :stop],
      %{duration_us: 1_750},
      %{partition_id: 1, signal_id: "signal-1"}
    )

    :telemetry.execute(
      [:jido_conversation, :runtime, :abort, :latency],
      %{duration_us: 2_500},
      %{partition_id: 1, signal_id: "signal-2"}
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
        signal_id: "signal-4",
        signal_type: "conv.in.message.received",
        subscription_id: "sub-1",
        error: :test_error
      }
    )

    snapshot =
      eventually(fn ->
        current = Telemetry.snapshot()

        if current.retry_count >= 1 and current.dlq_count >= 1 and
             current.dispatch_failure_count >= 1 do
          {:ok, current}
        else
          :retry
        end
      end)

    assert snapshot.queue_depth.total == 3
    assert snapshot.queue_depth.by_partition[1] == 3
    assert snapshot.apply_latency_ms.count == 1
    assert snapshot.apply_latency_ms.avg_ms > 0.0
    assert snapshot.abort_latency_ms.count == 1
    assert snapshot.retry_count == 1
    assert snapshot.dlq_count == 1
    assert snapshot.dispatch_failure_count == 1
    assert snapshot.last_dispatch_failure.signal_id == "signal-4"
  end

  test "reset clears metrics to baseline" do
    :telemetry.execute(
      [:jido_conversation, :runtime, :queue, :depth],
      %{depth: 7},
      %{partition_id: 3}
    )

    _snapshot =
      eventually(fn ->
        current = Telemetry.snapshot()
        if current.queue_depth.total > 0, do: {:ok, current}, else: :retry
      end)

    assert :ok = Telemetry.reset()

    reset_snapshot = Telemetry.snapshot()
    assert reset_snapshot.queue_depth.total == 0
    assert reset_snapshot.retry_count == 0
    assert reset_snapshot.dlq_count == 0
    assert reset_snapshot.dispatch_failure_count == 0
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
