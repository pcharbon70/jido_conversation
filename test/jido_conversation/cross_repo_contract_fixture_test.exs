defmodule JidoConversation.CrossRepoContractFixtureTest do
  use ExUnit.Case, async: false

  alias JidoConversation.Ingest
  alias JidoConversation.Projections
  alias JidoConversation.Projections.LlmContext
  alias JidoConversation.Projections.Timeline

  @fixture_path "test/fixtures/cross_repo/user_strategy_tool_strategy_trace.json"

  test "shared fixture canonical trace preserves projection and replay parity" do
    fixture = load_fixture!()
    conversation_id = unique_id("cross-repo-fixture")
    replay_start = DateTime.utc_now() |> DateTime.to_unix()

    ingest_canonical_fixture_trace!(fixture, conversation_id)

    live_timeline = Projections.timeline(conversation_id, coalesce_deltas: false)
    live_context = Projections.llm_context(conversation_id, include_deltas: true)

    expected_types = fixture["expected"]["canonical_timeline_types"]
    expected_tool_statuses = fixture["expected"]["canonical_tool_statuses"]

    case contract_drift_diagnostics(live_timeline, expected_types, expected_tool_statuses) do
      :ok ->
        :ok

      {:error, diagnostics} ->
        flunk(diagnostics)
    end

    replay_signals =
      eventually(fn ->
        case Ingest.replay("conv.**", replay_start) do
          {:ok, records} ->
            signals =
              records
              |> Enum.map(& &1.signal)
              |> Enum.filter(&(&1.subject == conversation_id))
              |> Enum.reject(&String.starts_with?(&1.type, "conv.applied."))

            if length(signals) >= length(expected_types), do: {:ok, signals}, else: :retry

          _other ->
            :retry
        end
      end)

    replay_timeline = Timeline.from_events(replay_signals, coalesce_deltas: false)
    replay_context = LlmContext.from_events(replay_signals, include_deltas: true)

    assert live_timeline == replay_timeline
    assert live_context == replay_context

    assert Enum.map(tool_entries(live_timeline), & &1.metadata.status) == expected_tool_statuses
  end

  test "shared fixture canonical trace is deterministic across repeated runs" do
    fixture = load_fixture!()

    signatures =
      Enum.map(1..2, fn _index ->
        conversation_id = unique_id("cross-repo-determinism")
        ingest_canonical_fixture_trace!(fixture, conversation_id)

        timeline = Projections.timeline(conversation_id, coalesce_deltas: false)
        context = Projections.llm_context(conversation_id, include_deltas: true)

        %{
          timeline_types: Enum.map(timeline, & &1.type),
          tool_statuses: Enum.map(tool_entries(timeline), & &1.metadata.status),
          context_roles: Enum.map(context, & &1.role),
          context_contents: Enum.map(context, & &1.content)
        }
      end)

    assert signatures == [hd(signatures), hd(signatures)]
  end

  defp ingest_canonical_fixture_trace!(fixture, conversation_id) do
    canonical_events = fixture["canonical_events"] || []

    Enum.with_index(canonical_events, 1)
    |> Enum.each(fn {event, index} ->
      attrs = %{
        id: "fixture-#{String.pad_leading(Integer.to_string(index), 3, "0")}",
        type: event["type"],
        source: "/tests/cross_repo_contract_fixture",
        subject: conversation_id,
        data: event["data"] || %{},
        extensions: %{"contract_major" => 1}
      }

      assert {:ok, %{status: :published}} = Ingest.ingest(attrs)
    end)
  end

  defp tool_entries(timeline) do
    Enum.filter(timeline, &(&1.type == "conv.out.tool.status"))
  end

  defp load_fixture! do
    @fixture_path
    |> File.read!()
    |> Jason.decode!()
  end

  defp unique_id(prefix) do
    "#{prefix}-#{System.unique_integer([:positive, :monotonic])}"
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

  defp contract_drift_diagnostics(timeline, expected_types, expected_tool_statuses) do
    observed_types = Enum.map(timeline, & &1.type)
    observed_tool_statuses = Enum.map(tool_entries(timeline), & &1.metadata.status)

    cond do
      observed_types != expected_types ->
        {:error,
         """
         contract drift: canonical timeline order/types do not match fixture
         expected timeline types: #{inspect(expected_types)}
         observed timeline types: #{inspect(observed_types)}
         """}

      observed_tool_statuses != expected_tool_statuses ->
        {:error,
         """
         contract drift: canonical tool status order does not match fixture
         expected tool statuses: #{inspect(expected_tool_statuses)}
         observed tool statuses: #{inspect(observed_tool_statuses)}
         """}

      true ->
        :ok
    end
  end
end
