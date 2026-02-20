defmodule JidoConversation.OperationsTest do
  use ExUnit.Case, async: false

  alias Jido.Signal.Error.ExecutionFailureError
  alias JidoConversation.Ingest
  alias JidoConversation.Operations

  defmodule AlwaysFailDispatchAdapter do
    @behaviour Jido.Signal.Dispatch.Adapter

    @impl true
    def validate_opts(opts) when is_list(opts) do
      case Keyword.get(opts, :target) do
        target when is_pid(target) ->
          {:ok, Keyword.put(opts, :delivery_mode, :async)}

        _other ->
          {:error, :invalid_fail_dispatch_opts}
      end
    end

    @impl true
    def deliver(_signal, _opts), do: {:error, :forced_dispatch_failure}
  end

  test "replay_conversation filters by conversation subject" do
    replay_start = DateTime.utc_now() |> DateTime.to_unix()
    conversation_a = unique_id("conversation-a")
    conversation_b = unique_id("conversation-b")

    assert {:ok, %{signal: signal_a}} =
             Ingest.ingest(%{
               type: "conv.in.message.received",
               source: "/messaging/test",
               subject: conversation_a,
               data: %{message_id: unique_id("msg"), ingress: "test"},
               extensions: %{"contract_major" => 1}
             })

    assert {:ok, _} =
             Ingest.ingest(%{
               type: "conv.in.message.received",
               source: "/messaging/test",
               subject: conversation_b,
               data: %{message_id: unique_id("msg"), ingress: "test"},
               extensions: %{"contract_major" => 1}
             })

    assert {:ok, records} =
             Operations.replay_conversation(conversation_a, start_timestamp: replay_start)

    assert Enum.any?(records, &(&1.signal.id == signal_a.id))
    assert Enum.all?(records, &(&1.signal.subject == conversation_a))
  end

  test "trace_cause_effect and record_audit_trace expose causality chain" do
    conversation_id = unique_id("conversation")
    replay_start = DateTime.utc_now() |> DateTime.to_unix()

    assert {:ok, %{signal: root_signal}} =
             Ingest.ingest(%{
               type: "conv.in.message.received",
               source: "/messaging/test",
               subject: conversation_id,
               data: %{message_id: unique_id("msg"), ingress: "test"},
               extensions: %{"contract_major" => 1}
             })

    assert {:ok, %{signal: child_signal}} =
             Ingest.ingest(
               %{
                 type: "conv.effect.tool.execution.started",
                 source: "/tool/runtime",
                 subject: conversation_id,
                 data: %{effect_id: unique_id("effect"), lifecycle: "started"},
                 extensions: %{"contract_major" => 1}
               },
               cause_id: root_signal.id
             )

    chain = Operations.trace_cause_effect(child_signal.id, :backward)
    chain_ids = Enum.map(chain, & &1.id)

    assert root_signal.id in chain_ids
    assert child_signal.id in chain_ids

    assert {:ok, %{audit_signal: audit_signal}} =
             Operations.record_audit_trace(child_signal.id, :backward, category: "policy_trace")

    assert audit_signal.type == "conv.audit.trace.chain_recorded"
    assert audit_signal.subject == conversation_id

    assert {:ok, replayed} =
             Ingest.replay("conv.audit.trace.chain_recorded", replay_start)

    assert Enum.any?(replayed, &(&1.signal.id == audit_signal.id))
  end

  test "stream_subscriptions and checkpoints expose subscription state" do
    subscription_id = unique_id("sub")

    assert {:ok, ^subscription_id} =
             Operations.subscribe_stream(
               "conv.audit.phase7.**",
               subscription_id: subscription_id,
               persistent?: true,
               dispatch: {:pid, target: self()}
             )

    on_exit(fn ->
      _ = Operations.unsubscribe_stream(subscription_id)
    end)

    subscriptions =
      eventually(fn ->
        case Operations.stream_subscriptions() do
          {:ok, current} ->
            if Enum.any?(current, &(&1.subscription_id == subscription_id)) do
              {:ok, current}
            else
              :retry
            end

          {:error, _reason} ->
            :retry
        end
      end)

    assert Enum.any?(subscriptions, &(&1.subscription_id == subscription_id))

    checkpoints =
      eventually(fn ->
        case Operations.checkpoints() do
          {:ok, current} ->
            if Enum.any?(current, &(&1.subscription_id == subscription_id)) do
              {:ok, current}
            else
              :retry
            end

          {:error, _reason} ->
            :retry
        end
      end)

    checkpoint = Enum.find(checkpoints, &(&1.subscription_id == subscription_id))
    assert is_integer(checkpoint.checkpoint)
    assert checkpoint.max_in_flight > 0
    assert checkpoint.max_pending > 0
    assert checkpoint.max_attempts > 0
    assert checkpoint.retry_interval > 0
  end

  test "launch_readiness summarizes health and runtime state" do
    wait_for_runtime_healthy!()

    report =
      eventually(fn ->
        case Operations.launch_readiness(max_queue_depth: 10_000, max_dispatch_failures: 10_000) do
          {:ok, %{status: :not_ready}} -> :retry
          {:ok, result} -> {:ok, result}
        end
      end)

    assert report.status in [:ready, :warning]
    assert report.health.status == :ok
    assert is_map(report.telemetry)
    assert is_map(report.subscriptions)
    assert is_map(report.checkpoints)
    assert is_map(report.dlq)
    assert is_list(report.issues)
  end

  test "launch_readiness warns when DLQ entries are present" do
    subscription_id = unique_id("launch-readiness-dlq")
    path = "conv.audit.operations.launch_readiness.dlq"
    conversation_id = unique_id("conversation")

    wait_for_runtime_healthy!()

    assert {:ok, ^subscription_id} =
             subscribe_with_retry(
               path,
               subscription_id: subscription_id,
               persistent?: true,
               max_attempts: 2,
               retry_interval: 5,
               max_in_flight: 5,
               max_pending: 20,
               dispatch: {AlwaysFailDispatchAdapter, target: self()}
             )

    on_exit(fn ->
      _ = Operations.unsubscribe_stream(subscription_id)
    end)

    assert {:ok, _} =
             Ingest.ingest(%{
               type: path,
               source: "/tests/operations",
               subject: conversation_id,
               data: %{audit_id: unique_id("audit"), category: "launch_readiness"},
               extensions: %{"contract_major" => 1}
             })

    eventually(fn ->
      case Operations.dlq_entries(subscription_id) do
        {:ok, []} -> :retry
        {:ok, _entries} -> {:ok, :ready}
        {:error, _reason} -> :retry
      end
    end)

    report =
      eventually(fn ->
        case Operations.launch_readiness(max_queue_depth: 10_000, max_dispatch_failures: 10_000) do
          {:ok, %{status: :not_ready}} -> :retry
          {:ok, result} -> {:ok, result}
        end
      end)

    assert report.status == :warning
    assert report.dlq.total_entries > 0

    assert Enum.any?(report.issues, fn issue ->
             issue.check == :dlq and issue.severity == :warning
           end)
  end

  test "record_launch_readiness_snapshot stores audit event and exposes it in history" do
    wait_for_runtime_healthy!()

    subject = unique_id("launch-readiness-history")
    start_timestamp = DateTime.utc_now() |> DateTime.to_unix()

    assert {:ok, %{report: report, audit_signal: audit_signal}} =
             Operations.record_launch_readiness_snapshot(
               subject: subject,
               max_queue_depth: 10_000,
               max_dispatch_failures: 10_000
             )

    assert audit_signal.type == "conv.audit.launch_readiness.snapshot_recorded"
    assert audit_signal.subject == subject

    {_entries, entry} =
      eventually(fn ->
        case Operations.launch_readiness_history(
               start_timestamp: start_timestamp,
               subject: subject
             ) do
          {:ok, entries} ->
            case Enum.find(entries, &(&1.signal_id == audit_signal.id)) do
              nil -> :retry
              found -> {:ok, {entries, found}}
            end

          {:error, _reason} ->
            :retry
        end
      end)

    assert entry.status == report.status
    assert entry.subject == subject
    assert entry.issue_counts.total >= entry.issue_counts.critical + entry.issue_counts.warning
    assert entry.thresholds.max_queue_depth == 10_000
    assert entry.thresholds.max_dispatch_failures == 10_000
    assert is_integer(entry.checked_at_unix_ms)
    assert %DateTime{} = entry.checked_at
  end

  test "launch_readiness_history supports subject and limit filters" do
    wait_for_runtime_healthy!()

    subject_a = unique_id("launch-readiness-a")
    subject_b = unique_id("launch-readiness-b")

    assert {:ok, _result} = Operations.record_launch_readiness_snapshot(subject: subject_a)
    assert {:ok, _result} = Operations.record_launch_readiness_snapshot(subject: subject_b)

    entries =
      eventually(fn ->
        case Operations.launch_readiness_history(subject: subject_a, limit: 1) do
          {:ok, []} ->
            :retry

          {:ok, result} ->
            {:ok, result}

          {:error, _reason} ->
            :retry
        end
      end)

    assert length(entries) == 1
    assert Enum.all?(entries, &(&1.subject == subject_a))
  end

  defp unique_id(prefix) do
    "#{prefix}-#{System.unique_integer([:positive, :monotonic])}"
  end

  defp subscribe_with_retry(path, opts, attempts \\ 120)

  defp subscribe_with_retry(_path, _opts, 0), do: raise("subscription not created in time")

  defp subscribe_with_retry(path, opts, attempts) do
    subscription_id = Keyword.fetch!(opts, :subscription_id)

    case Operations.subscribe_stream(path, opts) do
      {:ok, ^subscription_id} = ok ->
        ok

      {:error, %ExecutionFailureError{details: %{reason: {:already_started, _pid}}}} ->
        Process.sleep(20)
        subscribe_with_retry(path, opts, attempts - 1)

      {:error, %ExecutionFailureError{details: %{reason: :subscription_exists}}} ->
        Process.sleep(20)
        subscribe_with_retry(path, opts, attempts - 1)

      {:error, _reason} ->
        Process.sleep(20)
        subscribe_with_retry(path, opts, attempts - 1)
    end
  end

  defp wait_for_runtime_healthy! do
    eventually(fn ->
      case JidoConversation.health() do
        %{status: :ok} -> {:ok, :ready}
        _other -> :retry
      end
    end)
  end

  defp eventually(fun, attempts \\ 120)

  defp eventually(_fun, 0), do: raise("condition not met within timeout")

  defp eventually(fun, attempts) do
    case fun.() do
      {:ok, result} ->
        result

      :retry ->
        Process.sleep(20)
        eventually(fun, attempts - 1)
    end
  end
end
