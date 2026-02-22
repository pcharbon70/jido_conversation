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

  test "aggregates llm lifecycle, stream, cancel, and retry metrics" do
    baseline = Telemetry.snapshot()
    now_us = System.monotonic_time(:microsecond)

    :telemetry.execute(
      [:jido_conversation, :runtime, :llm, :lifecycle],
      %{count: 1, timestamp_us: now_us},
      %{
        effect_id: "llm-1",
        conversation_id: "c-1",
        lifecycle: "started",
        backend: "jido_ai",
        provider: "anthropic",
        model: "claude"
      }
    )

    :telemetry.execute(
      [:jido_conversation, :runtime, :llm, :lifecycle],
      %{count: 1, timestamp_us: now_us + 800},
      %{
        effect_id: "llm-1",
        conversation_id: "c-1",
        lifecycle: "progress",
        backend: "jido_ai",
        provider: "anthropic",
        model: "claude",
        token_delta?: true
      }
    )

    :telemetry.execute(
      [:jido_conversation, :runtime, :llm, :lifecycle],
      %{count: 1, timestamp_us: now_us + 1_400},
      %{
        effect_id: "llm-1",
        conversation_id: "c-1",
        lifecycle: "progress",
        backend: "jido_ai",
        provider: "anthropic",
        model: "claude",
        thinking_delta?: true
      }
    )

    :telemetry.execute(
      [:jido_conversation, :runtime, :llm, :lifecycle],
      %{count: 1, timestamp_us: now_us + 2_100},
      %{
        effect_id: "llm-1",
        conversation_id: "c-1",
        lifecycle: "completed",
        backend: "jido_ai",
        provider: "anthropic",
        model: "claude"
      }
    )

    :telemetry.execute(
      [:jido_conversation, :runtime, :llm, :lifecycle],
      %{count: 1, timestamp_us: now_us + 2_500},
      %{
        effect_id: "llm-2",
        conversation_id: "c-1",
        lifecycle: "started",
        backend: "harness",
        provider: "codex",
        model: "default"
      }
    )

    :telemetry.execute(
      [:jido_conversation, :runtime, :llm, :lifecycle],
      %{count: 1, timestamp_us: now_us + 3_100},
      %{
        effect_id: "llm-2",
        conversation_id: "c-1",
        lifecycle: "failed",
        backend: "harness",
        provider: "codex",
        model: "default",
        error_category: "provider"
      }
    )

    :telemetry.execute(
      [:jido_conversation, :runtime, :llm, :lifecycle],
      %{count: 1, timestamp_us: now_us + 3_600},
      %{
        effect_id: "llm-3",
        conversation_id: "c-1",
        lifecycle: "started",
        backend: "jido_ai",
        provider: "anthropic",
        model: "claude"
      }
    )

    :telemetry.execute(
      [:jido_conversation, :runtime, :llm, :retry],
      %{count: 1, backoff_ms: 100},
      %{
        effect_id: "llm-3",
        conversation_id: "c-1",
        retry_category: "timeout",
        backend: "jido_ai"
      }
    )

    :telemetry.execute(
      [:jido_conversation, :runtime, :llm, :cancel],
      %{duration_us: 1_200},
      %{
        effect_id: "llm-3",
        conversation_id: "c-1",
        cancel_result: "ok",
        backend: "jido_ai"
      }
    )

    :telemetry.execute(
      [:jido_conversation, :runtime, :llm, :lifecycle],
      %{count: 1, timestamp_us: now_us + 4_100},
      %{
        effect_id: "llm-3",
        conversation_id: "c-1",
        lifecycle: "canceled",
        backend: "jido_ai",
        provider: "anthropic",
        model: "claude",
        cancel_result: "ok"
      }
    )

    snapshot =
      eventually(fn ->
        current = Telemetry.snapshot()
        llm = current.llm
        baseline_llm = baseline.llm

        if llm.lifecycle_counts.started >= baseline_llm.lifecycle_counts.started + 3 and
             llm.lifecycle_counts.completed >= baseline_llm.lifecycle_counts.completed + 1 and
             llm.lifecycle_counts.failed >= baseline_llm.lifecycle_counts.failed + 1 and
             llm.lifecycle_counts.canceled >= baseline_llm.lifecycle_counts.canceled + 1 and
             llm.stream_duration_ms.count >= baseline_llm.stream_duration_ms.count + 3 and
             llm.stream_chunks.total >= baseline_llm.stream_chunks.total + 2 and
             llm.cancel_latency_ms.count >= baseline_llm.cancel_latency_ms.count + 1 do
          {:ok, current}
        else
          :retry
        end
      end)

    llm = snapshot.llm

    assert llm.lifecycle_by_backend["jido_ai"].completed >= 1
    assert llm.lifecycle_by_backend["harness"].failed >= 1
    assert llm.stream_chunks.delta >= 1
    assert llm.stream_chunks.thinking >= 1
    assert llm.retry_by_category["timeout"] >= 1
    assert llm.cancel_results["ok"] >= 1
    assert llm.cancel_latency_ms.avg_ms > 0.0
  end

  test "llm retry metrics prefer retry_category and fall back to error_category" do
    baseline = Telemetry.snapshot().llm

    :telemetry.execute(
      [:jido_conversation, :runtime, :llm, :retry],
      %{count: 1, backoff_ms: 10},
      %{
        effect_id: "llm-retry-provider",
        conversation_id: "c-1",
        retry_category: "provider",
        backend: "jido_ai"
      }
    )

    :telemetry.execute(
      [:jido_conversation, :runtime, :llm, :retry],
      %{count: 1, backoff_ms: 15},
      %{
        effect_id: "llm-retry-transport-fallback",
        conversation_id: "c-1",
        error_category: "transport",
        backend: "jido_ai"
      }
    )

    :telemetry.execute(
      [:jido_conversation, :runtime, :llm, :retry],
      %{count: 1, backoff_ms: 20},
      %{
        effect_id: "llm-retry-prefer-retry-category",
        conversation_id: "c-1",
        retry_category: "timeout",
        error_category: "provider",
        backend: "harness"
      }
    )

    :telemetry.execute(
      [:jido_conversation, :runtime, :llm, :retry],
      %{count: 1, backoff_ms: 25},
      %{
        effect_id: "llm-retry-empty-category",
        conversation_id: "c-1",
        retry_category: "   ",
        backend: "harness"
      }
    )

    llm =
      eventually(fn ->
        current = Telemetry.snapshot().llm

        provider = Map.get(current.retry_by_category, "provider", 0)
        transport = Map.get(current.retry_by_category, "transport", 0)
        timeout = Map.get(current.retry_by_category, "timeout", 0)

        base_provider = Map.get(baseline.retry_by_category, "provider", 0)
        base_transport = Map.get(baseline.retry_by_category, "transport", 0)
        base_timeout = Map.get(baseline.retry_by_category, "timeout", 0)

        if provider >= base_provider + 1 and
             transport >= base_transport + 1 and
             timeout >= base_timeout + 1 do
          {:ok, current}
        else
          :retry
        end
      end)

    assert Map.get(llm.retry_by_category, "provider", 0) ==
             Map.get(baseline.retry_by_category, "provider", 0) + 1

    assert Map.get(llm.retry_by_category, "transport", 0) ==
             Map.get(baseline.retry_by_category, "transport", 0) + 1

    assert Map.get(llm.retry_by_category, "timeout", 0) ==
             Map.get(baseline.retry_by_category, "timeout", 0) + 1
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

    assert reset_snapshot.llm.lifecycle_counts == %{
             started: 0,
             progress: 0,
             completed: 0,
             failed: 0,
             canceled: 0
           }

    assert reset_snapshot.llm.stream_chunks == %{delta: 0, thinking: 0, total: 0}
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
