defmodule JidoConversation.RolloutTest do
  use ExUnit.Case, async: false

  alias JidoConversation.Config
  alias JidoConversation.Ingest
  alias JidoConversation.Rollout
  alias JidoConversation.Rollout.Parity.NoopLegacyAdapter
  alias JidoConversation.Rollout.ParityAdapter
  alias JidoConversation.Rollout.Reporter
  alias JidoConversation.Signal.Contract

  defmodule MatchingLegacyAdapter do
    @behaviour ParityAdapter

    @impl true
    def outputs_for_conversation(conversation_id, _opts) do
      {:ok,
       [
         %{
           type: "conv.out.assistant.completed",
           subject: conversation_id,
           data: %{output_id: "assistant-1", channel: "web", content: "hello"}
         }
       ]}
    end
  end

  setup do
    original = Application.get_env(:jido_conversation, JidoConversation.EventSystem, [])
    :ok = Reporter.reset()

    on_exit(fn ->
      Application.put_env(:jido_conversation, JidoConversation.EventSystem, original)
      Config.validate!()
      :ok = Reporter.reset()
    end)

    :ok
  end

  test "event-based mode enqueues when canary is disabled" do
    set_rollout!(
      mode: :event_based,
      canary: [enabled: false, subjects: [], tenant_ids: [], channels: []],
      parity: [
        enabled: false,
        sample_rate: 1.0,
        max_reports: 50,
        legacy_adapter: MatchingLegacyAdapter
      ]
    )

    decision = Rollout.decide(conversation_signal("conversation-rollout-1"))

    assert decision.mode == :event_based
    assert decision.action == :enqueue_runtime
    assert decision.reason == :enabled
    assert decision.canary_match?
    refute decision.parity_sampled?
  end

  test "event-based mode drops when canary filtering excludes the signal" do
    set_rollout!(
      mode: :event_based,
      canary: [enabled: true, subjects: ["other-conversation"], tenant_ids: [], channels: []],
      parity: [
        enabled: true,
        sample_rate: 1.0,
        max_reports: 50,
        legacy_adapter: MatchingLegacyAdapter
      ]
    )

    decision = Rollout.decide(conversation_signal("conversation-rollout-2"))

    assert decision.action == :drop
    assert decision.reason == :canary_filtered
    refute decision.canary_match?
    refute decision.parity_sampled?
  end

  test "shadow mode enables parity-only decisions for canary-matched signals" do
    subject = "conversation-rollout-3"

    set_rollout!(
      mode: :shadow,
      canary: [enabled: true, subjects: [subject], tenant_ids: [], channels: []],
      parity: [
        enabled: true,
        sample_rate: 1.0,
        max_reports: 50,
        legacy_adapter: MatchingLegacyAdapter
      ]
    )

    decision = Rollout.decide(conversation_signal(subject))

    assert decision.mode == :shadow
    assert decision.action == :parity_only
    assert decision.reason == :shadow_mode
    assert decision.canary_match?
    assert decision.parity_sampled?
  end

  test "reporter aggregates decisions and parity samples" do
    signal = conversation_signal("conversation-rollout-4")

    decision = %{
      mode: :event_based,
      action: :enqueue_runtime,
      reason: :enabled,
      canary_match?: true,
      parity_sampled?: true,
      subject: signal.subject,
      tenant_id: nil,
      channel: "web"
    }

    :ok = Reporter.record_decision(decision)
    :ok = Reporter.record_parity_sample(signal, decision)

    snapshot =
      eventually(fn ->
        current = Reporter.snapshot()

        if current.decision_counts.enqueue_runtime >= 1 and current.parity_sample_count >= 1 do
          {:ok, current}
        else
          :retry
        end
      end)

    assert snapshot.decision_counts.enqueue_runtime >= 1
    assert snapshot.reason_counts.enabled >= 1
    assert snapshot.parity_sample_count >= 1
    assert snapshot.recent_parity_samples != []
  end

  test "parity comparison reports match when outputs align with adapter" do
    conversation_id = unique_id("conversation")
    replay_start = DateTime.utc_now() |> DateTime.to_unix()

    set_rollout!(
      mode: :event_based,
      canary: [enabled: false, subjects: [], tenant_ids: [], channels: []],
      parity: [
        enabled: true,
        sample_rate: 1.0,
        max_reports: 50,
        legacy_adapter: MatchingLegacyAdapter
      ]
    )

    assert {:ok, _} =
             Ingest.ingest(%{
               type: "conv.out.assistant.completed",
               source: "/tests/rollout",
               subject: conversation_id,
               data: %{output_id: "assistant-1", channel: "web", content: "hello"},
               extensions: %{"contract_major" => 1}
             })

    assert {:ok, report} =
             JidoConversation.rollout_parity_compare(conversation_id,
               start_timestamp: replay_start
             )

    assert report.status == :match
    assert report.missing_in_legacy == 0
    assert report.missing_in_event == 0
    assert report.event_output_count == 1
    assert report.legacy_output_count == 1

    snapshot =
      eventually(fn ->
        current = Reporter.snapshot()
        if current.parity_report_count >= 1, do: {:ok, current}, else: :retry
      end)

    assert snapshot.parity_report_count >= 1
  end

  test "parity comparison reports legacy adapter unavailability" do
    conversation_id = unique_id("conversation")

    set_rollout!(
      mode: :event_based,
      canary: [enabled: false, subjects: [], tenant_ids: [], channels: []],
      parity: [
        enabled: true,
        sample_rate: 1.0,
        max_reports: 50,
        legacy_adapter: NoopLegacyAdapter
      ]
    )

    assert {:ok, report} = JidoConversation.rollout_parity_compare(conversation_id)
    assert report.status == :legacy_unavailable
    assert report.reason == :legacy_adapter_not_configured
  end

  defp conversation_signal(subject) do
    Contract.normalize!(%{
      type: "conv.in.message.received",
      source: "/tests/rollout",
      subject: subject,
      data: %{message_id: unique_id("msg"), ingress: "web"},
      extensions: %{"contract_major" => 1}
    })
  end

  defp set_rollout!(rollout_cfg) when is_list(rollout_cfg) do
    current = Application.get_env(:jido_conversation, JidoConversation.EventSystem, [])
    updated = Keyword.put(current, :rollout, rollout_cfg)
    Application.put_env(:jido_conversation, JidoConversation.EventSystem, updated)
    Config.validate!()
  end

  defp unique_id(prefix) do
    "#{prefix}-#{System.unique_integer([:positive, :monotonic])}"
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
