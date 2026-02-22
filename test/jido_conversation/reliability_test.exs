defmodule Jido.Conversation.ReliabilityTest do
  use ExUnit.Case, async: false

  alias Jido.Conversation.Ingest
  alias Jido.Conversation.Runtime.Coordinator
  alias Jido.Conversation.Runtime.EffectManager
  alias Jido.Conversation.Runtime.IngressSubscriber
  alias Jido.Signal.Error.ExecutionFailureError

  setup do
    wait_for_ingress_subscriber!()
    wait_for_runtime_idle!()

    on_exit(fn ->
      wait_for_runtime_idle!()
    end)

    :ok
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
