defmodule JidoConversation.Runtime.EffectManagerTest do
  use ExUnit.Case, async: false

  alias JidoConversation.Ingest
  alias JidoConversation.Runtime.Coordinator
  alias JidoConversation.Runtime.EffectManager
  alias JidoConversation.Runtime.IngressSubscriber

  setup do
    wait_for_ingress_subscriber!()
    wait_for_runtime_idle!()
    on_exit(fn -> wait_for_runtime_idle!() end)
    :ok
  end

  test "start_effect emits started/progress/completed lifecycle and clears in-flight state" do
    conversation_id = unique_id("conversation")
    effect_id = unique_id("effect")
    replay_start = DateTime.utc_now() |> DateTime.to_unix()

    :ok =
      EffectManager.start_effect(
        %{
          effect_id: effect_id,
          conversation_id: conversation_id,
          class: :tool,
          kind: "execution",
          input: %{tool_name: "read_file"},
          simulate: %{latency_ms: 5},
          policy: %{max_attempts: 2, backoff_ms: 5, timeout_ms: 120}
        },
        nil
      )

    assert {:ok, recorded} =
             eventually(fn ->
               case Ingest.replay("conv.effect.tool.execution.**", replay_start) do
                 {:ok, events} ->
                   lifecycles = effect_lifecycles(events, effect_id)

                   if includes_all?(lifecycles, ["started", "progress", "completed"]) do
                     {:ok, {:ok, events}}
                   else
                     :retry
                   end

                 other ->
                   {:ok, other}
               end
             end)

    refute Enum.any?(recorded, fn event ->
             effect_id_for(event) == effect_id and lifecycle_for(event) == "failed"
           end)

    eventually(fn ->
      if EffectManager.stats().in_flight_count == 0 do
        {:ok, :ok}
      else
        :retry
      end
    end)
  end

  test "timeout retries and emits failed lifecycle after attempts are exhausted" do
    conversation_id = unique_id("conversation")
    effect_id = unique_id("effect")
    replay_start = DateTime.utc_now() |> DateTime.to_unix()

    :ok =
      EffectManager.start_effect(
        %{
          effect_id: effect_id,
          conversation_id: conversation_id,
          class: :llm,
          kind: "generation",
          input: %{prompt: "hello"},
          simulate: %{latency_ms: 80},
          policy: %{max_attempts: 2, backoff_ms: 5, timeout_ms: 10}
        },
        nil
      )

    assert {:ok, recorded} =
             eventually(fn ->
               case Ingest.replay("conv.effect.llm.generation.**", replay_start) do
                 {:ok, events} ->
                   lifecycles = effect_lifecycles(events, effect_id)

                   if includes_all?(lifecycles, ["started", "failed"]) do
                     {:ok, {:ok, events}}
                   else
                     :retry
                   end

                 other ->
                   {:ok, other}
               end
             end)

    assert Enum.any?(recorded, fn event ->
             effect_id_for(event) == effect_id and lifecycle_for(event) == "failed" and
               to_integer(data_field(event, :attempt, 0)) == 2
           end)

    eventually(fn ->
      if EffectManager.stats().in_flight_count == 0 do
        {:ok, :ok}
      else
        :retry
      end
    end)
  end

  test "invalid cause_id falls back to uncoupled lifecycle ingestion" do
    conversation_id = unique_id("conversation")
    effect_id = unique_id("effect")
    replay_start = DateTime.utc_now() |> DateTime.to_unix()

    :ok =
      EffectManager.start_effect(
        %{
          effect_id: effect_id,
          conversation_id: conversation_id,
          class: :tool,
          kind: "execution",
          input: %{tool_name: "read_file"},
          simulate: %{latency_ms: 5},
          policy: %{max_attempts: 1, backoff_ms: 5, timeout_ms: 120}
        },
        unique_id("unknown-cause")
      )

    assert {:ok, _recorded} =
             eventually(fn ->
               case Ingest.replay("conv.effect.tool.execution.**", replay_start) do
                 {:ok, events} ->
                   lifecycles = effect_lifecycles(events, effect_id)

                   if includes_all?(lifecycles, ["started", "completed"]) do
                     {:ok, {:ok, events}}
                   else
                     :retry
                   end

                 other ->
                   {:ok, other}
               end
             end)
  end

  test "cancel_conversation emits canceled lifecycle and cleans worker state" do
    conversation_id = unique_id("conversation")
    effect_id = unique_id("effect")
    replay_start = DateTime.utc_now() |> DateTime.to_unix()

    :ok =
      EffectManager.start_effect(
        %{
          effect_id: effect_id,
          conversation_id: conversation_id,
          class: :tool,
          kind: "execution",
          input: %{tool_name: "fetch"},
          simulate: %{latency_ms: 500},
          policy: %{max_attempts: 1, backoff_ms: 5, timeout_ms: 1_000}
        },
        nil
      )

    eventually(fn ->
      case Ingest.replay("conv.effect.tool.execution.started", replay_start) do
        {:ok, events} ->
          if Enum.any?(events, &(effect_id_for(&1) == effect_id)) do
            {:ok, :ok}
          else
            :retry
          end

        _ ->
          :retry
      end
    end)

    :ok = EffectManager.cancel_conversation(conversation_id, "user_abort", nil)

    assert {:ok, replayed} =
             eventually(fn ->
               case Ingest.replay("conv.effect.tool.execution.canceled", replay_start) do
                 {:ok, events} ->
                   matches = Enum.filter(events, &(effect_id_for(&1) == effect_id))
                   if matches == [], do: :retry, else: {:ok, {:ok, matches}}

                 other ->
                   {:ok, other}
               end
             end)

    assert Enum.any?(replayed, &(lifecycle_for(&1) == "canceled"))

    eventually(fn ->
      if EffectManager.stats().in_flight_count == 0 do
        {:ok, :ok}
      else
        :retry
      end
    end)
  end

  defp eventually(fun, attempts \\ 250)

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

  defp includes_all?(lifecycle_values, required_values) do
    lifecycle_set = MapSet.new(lifecycle_values)
    required_set = MapSet.new(required_values)
    MapSet.subset?(required_set, lifecycle_set)
  end

  defp effect_lifecycles(events, effect_id) do
    events
    |> Enum.filter(&(effect_id_for(&1) == effect_id))
    |> Enum.map(&lifecycle_for/1)
  end

  defp lifecycle_for(event) do
    data_field(event, :lifecycle, "")
  end

  defp effect_id_for(event) do
    data_field(event, :effect_id, nil)
  end

  defp data_field(event, key, default) do
    data = event.signal.data || %{}
    Map.get(data, key) || Map.get(data, to_string(key)) || default
  end

  defp to_integer(value) when is_integer(value), do: value

  defp to_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      _ -> 0
    end
  end

  defp to_integer(_value), do: 0

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
      coordinator_stats = Coordinator.stats()
      effect_stats = EffectManager.stats()

      partition_busy? =
        coordinator_stats.partitions
        |> Map.values()
        |> Enum.any?(fn partition ->
          partition.queue_size > 0
        end)

      if partition_busy? or effect_stats.in_flight_count > 0 do
        :retry
      else
        {:ok, :ready}
      end
    end)
  end
end
