defmodule JidoConversation.TelemetryTest do
  use ExUnit.Case, async: false

  alias JidoConversation.Telemetry

  setup do
    :ok = Telemetry.reset()
    :ok
  end

  test "aggregates runtime and dispatch metrics" do
    now = System.monotonic_time(:microsecond)
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

    snapshot =
      eventually(fn ->
        current = Telemetry.snapshot()

        if current.retry_count >= baseline.retry_count + 1 and
             current.dlq_count >= baseline.dlq_count + 1 and
             current.dispatch_failure_count >= baseline.dispatch_failure_count + 1 and
             current.apply_latency_ms.count >= baseline.apply_latency_ms.count + 1 and
             current.abort_latency_ms.count >= baseline.abort_latency_ms.count + 1 do
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
