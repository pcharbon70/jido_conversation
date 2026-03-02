defmodule JidoConversation.Phase7CutoverIntegrationTest do
  use ExUnit.Case, async: false

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
    :ok
  end

  test "legacy mode runtime surface is removed from jido_conversation" do
    refute function_exported?(JidoConversation, :mode, 1)
    refute function_exported?(JidoConversation, :supported_modes, 0)
    refute function_exported?(JidoConversation, :supported_mode_metadata, 0)
    refute function_exported?(JidoConversation, :supported_mode_metadata, 1)
    refute function_exported?(JidoConversation, :configure_mode, 2)
    refute function_exported?(JidoConversation, :configure_mode, 3)

    mode_files =
      Path.wildcard(Path.join([File.cwd!(), "lib/jido/conversation/mode*.ex"])) ++
        Path.wildcard(Path.join([File.cwd!(), "lib/jido/conversation/mode/**/*.ex"]))

    assert mode_files == []
  end

  test "canonical traces replay deterministically after mode-runtime cutover" do
    conversation_id = unique_id("phase7-cutover-conversation")
    correlation_id = unique_id("phase7-cutover-correlation")

    events = [
      %{
        id: unique_id("evt"),
        type: "conv.in.message.received",
        source: "/tests/phase7_cutover",
        subject: conversation_id,
        data: %{message_id: unique_id("msg"), ingress: "jido_code_server", content: "hello"},
        extensions: %{"contract_major" => 1, "correlation_id" => correlation_id}
      },
      %{
        id: unique_id("evt"),
        type: "conv.out.assistant.delta",
        source: "/tests/phase7_cutover",
        subject: conversation_id,
        data: %{
          output_id: "output-1",
          channel: "jido_code_server",
          delta: "working ",
          status: "progress",
          lifecycle: "progress"
        },
        extensions: %{"contract_major" => 1, "correlation_id" => correlation_id}
      },
      %{
        id: unique_id("evt"),
        type: "conv.out.tool.status",
        source: "/tests/phase7_cutover",
        subject: conversation_id,
        data: %{
          output_id: "tool-1",
          channel: "jido_code_server",
          status: "requested",
          lifecycle: "requested",
          tool_name: "asset.list",
          message: "tool requested"
        },
        extensions: %{"contract_major" => 1, "correlation_id" => correlation_id}
      },
      %{
        id: unique_id("evt"),
        type: "conv.out.tool.status",
        source: "/tests/phase7_cutover",
        subject: conversation_id,
        data: %{
          output_id: "tool-1",
          channel: "jido_code_server",
          status: "completed",
          lifecycle: "completed",
          tool_name: "asset.list",
          message: "tool completed"
        },
        extensions: %{"contract_major" => 1, "correlation_id" => correlation_id}
      },
      %{
        id: unique_id("evt"),
        type: "conv.out.assistant.completed",
        source: "/tests/phase7_cutover",
        subject: conversation_id,
        data: %{
          output_id: "output-1",
          channel: "jido_code_server",
          content: "working done",
          status: "completed",
          lifecycle: "completed"
        },
        extensions: %{"contract_major" => 1, "correlation_id" => correlation_id}
      }
    ]

    Enum.each(events, fn attrs ->
      assert {:ok, %{status: :published}} = Ingest.ingest(attrs)
    end)

    wait_for_runtime_idle!()

    canonical_events =
      eventually(fn ->
        loaded = Ingest.conversation_events(conversation_id)

        loaded_types = MapSet.new(Enum.map(loaded, & &1.type))
        required_types =
          MapSet.new([
            "conv.in.message.received",
            "conv.out.assistant.delta",
            "conv.out.tool.status",
            "conv.out.assistant.completed"
          ])

        if MapSet.subset?(required_types, loaded_types) do
          {:ok, loaded}
        else
          :retry
        end
      end)

    assert Enum.all?(canonical_events, &String.starts_with?(&1.type, "conv."))

    live_timeline = Projections.timeline(conversation_id)
    live_context = Projections.llm_context(conversation_id)

    replay_timeline = Timeline.from_events(canonical_events)
    replay_context = LlmContext.from_events(canonical_events)

    assert live_timeline == replay_timeline
    assert live_context == replay_context

    tool_statuses =
      canonical_events
      |> Enum.filter(&(&1.type == "conv.out.tool.status"))
      |> Enum.map(fn signal -> map_lookup(signal.data, :status) end)
      |> Enum.reject(&is_nil/1)

    assert "requested" in tool_statuses
    assert "completed" in tool_statuses
  end

  defp unique_id(prefix) do
    "#{prefix}-#{System.unique_integer([:positive, :monotonic])}"
  end

  defp map_lookup(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp map_lookup(_map, _key), do: nil

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
