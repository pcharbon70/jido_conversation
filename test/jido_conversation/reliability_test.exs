defmodule JidoConversation.ReliabilityTest do
  use ExUnit.Case, async: false

  alias Jido.Signal.Bus
  alias Jido.Signal.Bus.PersistentSubscription
  alias Jido.Signal.Error.ExecutionFailureError
  alias JidoConversation.Ingest
  alias JidoConversation.Runtime.Coordinator
  alias JidoConversation.Runtime.EffectManager
  alias JidoConversation.Runtime.IngressSubscriber

  defmodule FlakyDispatchAdapter do
    @behaviour Jido.Signal.Dispatch.Adapter

    @impl true
    def validate_opts(opts) when is_list(opts) do
      with tracker when is_pid(tracker) <- Keyword.get(opts, :tracker),
           target when is_pid(target) <- Keyword.get(opts, :target) do
        {:ok, Keyword.put(opts, :delivery_mode, :async)}
      else
        _ -> {:error, :invalid_flaky_dispatch_opts}
      end
    end

    @impl true
    def deliver(signal, opts) do
      tracker = Keyword.fetch!(opts, :tracker)
      target = Keyword.fetch!(opts, :target)

      case Agent.get(tracker, & &1) do
        :fail ->
          {:error, :forced_dispatch_failure}

        :ok ->
          send(target, {:flaky_dispatched, signal.id, signal.type})
          :ok
      end
    end
  end

  setup do
    wait_for_ingress_subscriber!()
    wait_for_runtime_idle!()
    cleanup_phase8_subscriptions()

    on_exit(fn ->
      cleanup_phase8_subscriptions()
      wait_for_runtime_idle!()
    end)

    :ok
  end

  test "persistent subscription checkpoint advances on ack and survives re-subscribe" do
    conversation_id = unique_id("conversation")
    subscription_id = unique_id("checkpoint-sub")
    path = "conv.audit.phase8.checkpoint"

    assert {:ok, ^subscription_id} =
             subscribe_phase8_stream(path, subscription_id, dispatch: {:pid, target: self()})

    on_exit(fn ->
      _ = force_remove_subscription(subscription_id)
    end)

    assert {:ok, %{signal: signal}} =
             ingest_with_backpressure_retry(%{
               type: path,
               source: "/tests/reliability",
               subject: conversation_id,
               data: %{audit_id: unique_id("audit"), category: "reliability"},
               extensions: %{"contract_major" => 1}
             })

    in_flight =
      eventually(fn ->
        case JidoConversation.subscription_in_flight(subscription_id) do
          {:ok, entries} ->
            matches = Enum.filter(entries, &(&1.signal_id == signal.id))
            if matches == [], do: :retry, else: {:ok, matches}

          _other ->
            :retry
        end
      end)

    signal_log_id = hd(in_flight).signal_log_id
    assert :ok = JidoConversation.ack_stream(subscription_id, signal_log_id)

    checkpoint_before =
      eventually(fn ->
        case JidoConversation.checkpoints() do
          {:ok, checkpoints} ->
            case Enum.find(checkpoints, &(&1.subscription_id == subscription_id)) do
              nil ->
                :retry

              checkpoint
              when checkpoint.in_flight_count == 0 and is_integer(checkpoint.checkpoint) ->
                {:ok, checkpoint.checkpoint}

              _other ->
                :retry
            end

          _other ->
            :retry
        end
      end)

    assert :ok = force_remove_subscription(subscription_id)

    assert {:ok, ^subscription_id} =
             subscribe_phase8_stream(path, subscription_id, dispatch: {:pid, target: self()})

    checkpoint_after =
      eventually(fn ->
        case JidoConversation.checkpoints() do
          {:ok, checkpoints} ->
            case Enum.find(checkpoints, &(&1.subscription_id == subscription_id)) do
              nil ->
                :retry

              checkpoint when is_integer(checkpoint.checkpoint) ->
                {:ok, checkpoint.checkpoint}

              _other ->
                :retry
            end

          _other ->
            :retry
        end
      end)

    assert checkpoint_after >= checkpoint_before
  end

  test "dlq redrive succeeds after transient dispatch failure recovers" do
    conversation_id = unique_id("conversation")
    subscription_id = unique_id("dlq-sub")
    path = "conv.audit.phase8.dlq"

    {:ok, tracker} = Agent.start_link(fn -> :fail end)

    on_exit(fn ->
      if Process.alive?(tracker) do
        Agent.stop(tracker, :normal)
      end
    end)

    assert {:ok, ^subscription_id} =
             subscribe_phase8_stream(path, subscription_id,
               max_attempts: 2,
               retry_interval: 5,
               max_in_flight: 5,
               max_pending: 20,
               dispatch: {FlakyDispatchAdapter, tracker: tracker, target: self()}
             )

    assert {:ok, _} =
             ingest_with_backpressure_retry(%{
               type: path,
               source: "/tests/reliability",
               subject: conversation_id,
               data: %{audit_id: unique_id("audit"), category: "reliability"},
               extensions: %{"contract_major" => 1}
             })

    entries =
      eventually(fn ->
        case JidoConversation.dlq_entries(subscription_id) do
          {:ok, items} when items != [] -> {:ok, items}
          _other -> :retry
        end
      end)

    assert entries != []

    Agent.update(tracker, fn _state -> :ok end)

    assert {:ok, %{succeeded: succeeded, failed: failed}} =
             JidoConversation.redrive_dlq(subscription_id, clear_on_success: true)

    assert succeeded >= 1
    assert failed == 0

    assert_receive {:flaky_dispatched, _signal_id, ^path}, 2_000

    assert {:ok, []} = JidoConversation.dlq_entries(subscription_id)
  end

  test "high-volume assistant delta stream drains and preserves output count" do
    conversation_id = unique_id("conversation")
    effect_id = unique_id("effect")
    replay_start = DateTime.utc_now() |> DateTime.to_unix()
    delta_count = 40

    for index <- 1..delta_count do
      assert {:ok, _} =
               ingest_with_backpressure_retry(%{
                 type: "conv.effect.llm.generation.progress",
                 source: "/tests/reliability",
                 subject: conversation_id,
                 data: %{effect_id: effect_id, lifecycle: "progress", token_delta: "t#{index} "},
                 extensions: %{"contract_major" => 1}
               })

      if rem(index, 10) == 0 do
        Process.sleep(5)
      end
    end

    assert {:ok, _} =
             ingest_with_backpressure_retry(%{
               type: "conv.effect.llm.generation.completed",
               source: "/tests/reliability",
               subject: conversation_id,
               data: %{effect_id: effect_id, lifecycle: "completed", result: %{text: "done"}},
               extensions: %{"contract_major" => 1}
             })

    replayed =
      eventually(
        fn ->
          case Ingest.replay("conv.out.assistant.**", replay_start) do
            {:ok, records} ->
              matches =
                Enum.filter(records, fn record ->
                  data = record.signal.data || %{}
                  (data[:effect_id] || data["effect_id"]) == effect_id
                end)

              if length(matches) >= delta_count + 1, do: {:ok, matches}, else: :retry

            _other ->
              :retry
          end
        end,
        600
      )

    deltas = Enum.filter(replayed, &(&1.signal.type == "conv.out.assistant.delta"))
    completed = Enum.filter(replayed, &(&1.signal.type == "conv.out.assistant.completed"))

    assert length(deltas) == delta_count
    assert length(completed) == 1

    eventually(
      fn ->
        stats = Coordinator.stats()
        effect_stats = EffectManager.stats()

        busy? =
          stats.partitions
          |> Map.values()
          |> Enum.any?(fn partition -> partition.queue_size > 0 end)

        if busy? or effect_stats.in_flight_count > 0, do: :retry, else: {:ok, :drained}
      end,
      600
    )
  end

  defp unique_id(prefix) do
    "#{prefix}-#{System.unique_integer([:positive, :monotonic])}"
  end

  defp subscribe_phase8_stream(path, subscription_id, opts) when is_list(opts) do
    subscribe_opts =
      [
        subscription_id: subscription_id,
        persistent?: true
      ] ++ opts

    eventually(fn ->
      case JidoConversation.subscribe_stream(path, subscribe_opts) do
        {:ok, ^subscription_id} = ok ->
          {:ok, ok}

        {:error, %ExecutionFailureError{details: %{reason: {:already_started, _pid}}}} ->
          :retry

        {:error, %ExecutionFailureError{details: %{reason: :subscription_exists}}} ->
          :retry

        {:error, _reason} ->
          :retry
      end
    end)
  end

  defp cleanup_phase8_subscriptions do
    case JidoConversation.stream_subscriptions() do
      {:ok, subscriptions} ->
        subscriptions
        |> Enum.filter(fn sub ->
          String.starts_with?(to_string(sub.path || ""), "conv.audit.phase8.")
        end)
        |> Enum.each(fn sub ->
          _ = force_remove_subscription(sub.subscription_id)
        end)

      _other ->
        :ok
    end
  end

  defp force_remove_subscription(subscription_id) when is_binary(subscription_id) do
    maybe_terminate_persistent_subscription(subscription_id)
    _ = JidoConversation.unsubscribe_stream(subscription_id)

    eventually(fn -> subscription_removed_result(subscription_id) end, 200)

    :ok
  end

  defp maybe_terminate_persistent_subscription(subscription_id) do
    case PersistentSubscription.whereis(subscription_id) do
      {:ok, pid} when is_pid(pid) ->
        terminate_persistent_subscription(pid)

      _other ->
        :ok
    end
  end

  defp persistent_subscription_alive?(subscription_id) do
    case PersistentSubscription.whereis(subscription_id) do
      {:ok, pid} when is_pid(pid) -> Process.alive?(pid)
      _other -> false
    end
  end

  defp terminate_persistent_subscription(pid) when is_pid(pid) do
    case bus_child_supervisor() do
      {:ok, child_supervisor} ->
        case DynamicSupervisor.terminate_child(child_supervisor, pid) do
          :ok -> :ok
          {:error, :not_found} -> terminate_process(pid)
          {:error, _reason} -> :ok
        end

      _other ->
        terminate_process(pid)
    end
  end

  defp terminate_process(pid) when is_pid(pid) do
    if Process.alive?(pid), do: Process.exit(pid, :shutdown)
    :ok
  end

  defp bus_child_supervisor do
    with {:ok, bus_pid} <- Bus.whereis(JidoConversation.Config.bus_name()),
         bus_state <- :sys.get_state(bus_pid),
         child_supervisor when is_pid(child_supervisor) <- Map.get(bus_state, :child_supervisor) do
      {:ok, child_supervisor}
    else
      _other ->
        {:error, :child_supervisor_not_found}
    end
  end

  defp subscription_present?(subscriptions, subscription_id) when is_list(subscriptions) do
    Enum.any?(subscriptions, &(&1.subscription_id == subscription_id))
  end

  defp subscription_removed_result(subscription_id) do
    case JidoConversation.stream_subscriptions() do
      {:ok, subscriptions} ->
        removed_result_from_subscriptions(subscriptions, subscription_id)

      _other ->
        :retry
    end
  end

  defp removed_result_from_subscriptions(subscriptions, subscription_id)
       when is_list(subscriptions) and is_binary(subscription_id) do
    if subscription_present?(subscriptions, subscription_id) or
         persistent_subscription_alive?(subscription_id) do
      :retry
    else
      {:ok, :removed}
    end
  end

  defp ingest_with_backpressure_retry(attrs, attempts \\ 80)

  defp ingest_with_backpressure_retry(_attrs, 0), do: {:error, :queue_backpressure_timeout}

  defp ingest_with_backpressure_retry(attrs, attempts) do
    case Ingest.ingest(attrs) do
      {:ok, _result} = ok ->
        ok

      {:error, {:publish_failed, %ExecutionFailureError{details: %{reason: :queue_full}}}} ->
        Process.sleep(10)
        ingest_with_backpressure_retry(attrs, attempts - 1)

      other ->
        other
    end
  end

  defp eventually(fun, attempts \\ 200)

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

  defp wait_for_ingress_subscriber! do
    eventually(fn ->
      case :sys.get_state(IngressSubscriber) do
        %{subscription_id: subscription_id} when is_binary(subscription_id) ->
          {:ok, :ready}

        _other ->
          :retry
      end
    end)
  end

  defp wait_for_runtime_idle! do
    eventually(fn ->
      stats = Coordinator.stats()
      effect_stats = EffectManager.stats()

      busy? =
        stats.partitions
        |> Map.values()
        |> Enum.any?(fn partition -> partition.queue_size > 0 end)

      if busy? or effect_stats.in_flight_count > 0 do
        :retry
      else
        {:ok, :ready}
      end
    end)
  end
end
