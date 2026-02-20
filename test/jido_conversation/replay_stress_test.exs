defmodule JidoConversation.ReplayStressTest do
  use ExUnit.Case, async: false

  alias Jido.Signal.Error.ExecutionFailureError
  alias Jido.Signal.ID
  alias JidoConversation.Ingest
  alias JidoConversation.Projections
  alias JidoConversation.Projections.LlmContext
  alias JidoConversation.Projections.Timeline
  alias JidoConversation.Runtime.Coordinator
  alias JidoConversation.Runtime.EffectManager
  alias JidoConversation.Runtime.IngressSubscriber

  setup do
    wait_for_ingress_subscriber!()
    wait_for_runtime_idle!()

    on_exit(fn ->
      wait_for_runtime_idle!()
    end)

    :ok
  end

  test "large audit traces remain fully replayable by stream pattern" do
    conversation_id = unique_id("conversation")
    replay_start = DateTime.utc_now() |> DateTime.to_unix()
    trace_size = 180

    trace_ids =
      for index <- 1..trace_size do
        signal_id = ID.generate!()

        assert {:ok, %{signal: signal}} =
                 ingest_with_backpressure_retry(%{
                   id: signal_id,
                   type: "conv.audit.policy.decision_recorded",
                   source: "/tests/replay-stress",
                   subject: conversation_id,
                   data: %{
                     audit_id: "audit-#{index}",
                     category: "policy",
                     decision: "allow"
                   },
                   extensions: %{"contract_major" => 1}
                 })

        if rem(index, 20) == 0 do
          Process.sleep(5)
        end

        signal.id
      end

    replayed =
      eventually(
        fn ->
          case Ingest.replay("conv.audit.**", replay_start) do
            {:ok, records} ->
              matches =
                Enum.filter(records, fn record ->
                  record.signal.subject == conversation_id and
                    record.signal.type == "conv.audit.policy.decision_recorded"
                end)

              match_ids = MapSet.new(Enum.map(matches, & &1.signal.id))

              if MapSet.subset?(MapSet.new(trace_ids), match_ids) do
                {:ok, matches}
              else
                :retry
              end

            _other ->
              :retry
          end
        end,
        600
      )

    assert length(replayed) == trace_size
  end

  test "large replayed output traces reconstruct timeline and llm context projections" do
    conversation_id = unique_id("conversation")
    output_id = unique_id("output")
    replay_start = DateTime.utc_now() |> DateTime.to_unix()
    delta_count = 100
    tool_count = 40

    delta_ids =
      for index <- 1..delta_count do
        assert {:ok, %{signal: signal}} =
                 ingest_with_backpressure_retry(%{
                   id: ID.generate!(),
                   type: "conv.out.assistant.delta",
                   source: "/tests/replay-stress",
                   subject: conversation_id,
                   data: %{
                     output_id: output_id,
                     channel: "web",
                     delta: "chunk-#{index} ",
                     effect_id: "effect-#{output_id}",
                     lifecycle: "progress",
                     chunk_index: index
                   },
                   extensions: %{"contract_major" => 1}
                 })

        if rem(index, 20) == 0 do
          Process.sleep(5)
        end

        signal.id
      end

    assert {:ok, %{signal: completed_signal}} =
             ingest_with_backpressure_retry(%{
               id: ID.generate!(),
               type: "conv.out.assistant.completed",
               source: "/tests/replay-stress",
               subject: conversation_id,
               data: %{
                 output_id: output_id,
                 channel: "web",
                 content: "done",
                 effect_id: "effect-#{output_id}",
                 lifecycle: "completed"
               },
               extensions: %{"contract_major" => 1}
             })

    tool_ids =
      for index <- 1..tool_count do
        assert {:ok, %{signal: signal}} =
                 ingest_with_backpressure_retry(%{
                   id: ID.generate!(),
                   type: "conv.out.tool.status",
                   source: "/tests/replay-stress",
                   subject: conversation_id,
                   data: %{
                     output_id: unique_id("tool-output"),
                     channel: "web",
                     status: "completed",
                     effect_id: "tool-effect-#{index}",
                     lifecycle: "completed",
                     message: "tool-#{index}"
                   },
                   extensions: %{"contract_major" => 1}
                 })

        if rem(index, 20) == 0 do
          Process.sleep(5)
        end

        signal.id
      end

    wait_for_runtime_idle!()

    live_timeline = Projections.timeline(conversation_id, coalesce_deltas: false)

    live_context =
      Projections.llm_context(conversation_id, include_deltas: true, max_messages: 500)

    replayed_out_signals =
      eventually(
        fn ->
          case Ingest.replay("conv.out.**", replay_start) do
            {:ok, records} ->
              matches =
                Enum.filter(records, fn record ->
                  record.signal.subject == conversation_id and
                    String.starts_with?(record.signal.type, "conv.out.")
                end)

              required_ids = MapSet.new(delta_ids ++ [completed_signal.id] ++ tool_ids)
              replayed_ids = MapSet.new(Enum.map(matches, & &1.signal.id))

              if MapSet.subset?(required_ids, replayed_ids) do
                {:ok, Enum.map(matches, & &1.signal)}
              else
                :retry
              end

            _other ->
              :retry
          end
        end,
        800
      )

    replay_timeline = Timeline.from_events(replayed_out_signals, coalesce_deltas: false)

    replay_context =
      LlmContext.from_events(replayed_out_signals, include_deltas: true, max_messages: 500)

    assert live_timeline == replay_timeline
    assert live_context == replay_context
    assert length(replay_timeline) == delta_count + tool_count + 1
  end

  defp ingest_with_backpressure_retry(attrs, attempts \\ 120)

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

  defp unique_id(prefix) do
    "#{prefix}-#{System.unique_integer([:positive, :monotonic])}"
  end
end
