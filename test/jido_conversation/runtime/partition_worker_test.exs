defmodule JidoConversation.Runtime.PartitionWorkerTest do
  use ExUnit.Case, async: false

  alias JidoConversation.Ingest
  alias JidoConversation.Runtime.Coordinator
  alias JidoConversation.Runtime.EffectManager
  alias JidoConversation.Runtime.IngressSubscriber
  alias JidoConversation.Runtime.PartitionWorker

  setup do
    wait_for_ingress_subscriber!()
    wait_for_runtime_idle!()
    :ok
  end

  test "causal readiness ensures cause event applies before dependent event" do
    conversation_id = unique_id("conversation")
    root_id = unique_id("root")
    child_id = unique_id("child")

    child_attrs = %{
      id: child_id,
      type: "conv.effect.tool.execution.started",
      source: "/tool/runtime",
      subject: conversation_id,
      data: %{effect_id: unique_id("effect"), lifecycle: "started"},
      extensions: %{"contract_major" => 1, "cause_id" => root_id}
    }

    root_attrs = %{
      id: root_id,
      type: "conv.in.message.received",
      source: "/messaging/test",
      subject: conversation_id,
      data: %{message_id: unique_id("msg"), ingress: "test"},
      extensions: %{"contract_major" => 1}
    }

    assert {:ok, %{signal: %{id: ^child_id}}} = Ingest.ingest(child_attrs)
    assert {:ok, %{signal: %{id: ^root_id}}} = Ingest.ingest(root_attrs)

    partition_id =
      Coordinator.partition_for_subject(
        conversation_id,
        JidoConversation.Config.runtime_partitions()
      )

    snapshot =
      eventually(fn ->
        snap = PartitionWorker.snapshot(partition_id)

        with %{^conversation_id => conversation} <- snap.conversations,
             true <- conversation.applied_count >= 2 do
          {:ok, snap}
        else
          _ -> :retry
        end
      end)

    conversation = snapshot.conversations[conversation_id]
    history_ids = Enum.map(conversation.history, & &1.id)

    assert Enum.take(history_ids, 2) == [root_id, child_id]
    assert snapshot.queue_size == 0
  end

  test "runtime emits conv.applied markers through ingestion pipeline" do
    conversation_id = unique_id("conversation")
    replay_start = DateTime.utc_now() |> DateTime.to_unix()

    attrs = %{
      type: "conv.in.message.received",
      source: "/messaging/test",
      subject: conversation_id,
      data: %{message_id: unique_id("msg"), ingress: "test"},
      extensions: %{"contract_major" => 1}
    }

    assert {:ok, %{signal: signal}} = Ingest.ingest(attrs)

    assert {:ok, replayed} =
             eventually(fn ->
               case Ingest.replay("conv.applied.**", replay_start) do
                 {:ok, recorded} ->
                   matches =
                     Enum.filter(recorded, fn record ->
                       record.signal.data["applied_event_id"] == signal.id or
                         record.signal.data[:applied_event_id] == signal.id
                     end)

                   if matches == [], do: :retry, else: {:ok, {:ok, matches}}

                 other ->
                   {:ok, other}
               end
             end)

    assert Enum.any?(replayed, fn record ->
             applied_event_id =
               record.signal.data["applied_event_id"] || record.signal.data[:applied_event_id]

             applied_event_id == signal.id
           end)
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

  defp unique_id(prefix) do
    "#{prefix}-#{System.unique_integer([:positive, :monotonic])}"
  end

  defp wait_for_ingress_subscriber! do
    eventually(fn ->
      case :sys.get_state(IngressSubscriber) do
        %{subscription_id: subscription_id} when is_binary(subscription_id) ->
          {:ok, :ready}

        _ ->
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
        |> Enum.any?(fn partition ->
          partition.queue_size > 0
        end)

      if busy? or effect_stats.in_flight_count > 0 do
        :retry
      else
        {:ok, :ready}
      end
    end)
  end
end
