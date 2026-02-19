defmodule JidoConversation.RolloutRunbookTest do
  use ExUnit.Case, async: false

  alias JidoConversation.Config
  alias JidoConversation.Rollout.Manager
  alias JidoConversation.Rollout.Reporter

  @app :jido_conversation
  @key JidoConversation.EventSystem

  setup do
    original_cfg = Application.get_env(@app, @key, [])

    :ok = Reporter.reset()
    :ok = Manager.reset()

    on_exit(fn ->
      Application.put_env(@app, @key, original_cfg)
      :ok = Config.validate!()
      :ok = Reporter.reset()
      :ok = Manager.reset()
    end)

    :ok
  end

  test "assess reports hold gate with volume collection actions" do
    put_rollout!(mode: :event_based, stage: :canary)

    assessment = JidoConversation.rollout_runbook_assess(apply?: false)

    assert assessment.gate == :hold
    assert assessment.verification_status == :hold
    assert :insufficient_runtime_decisions in assessment.verification_reasons
    assert :insufficient_parity_reports in assessment.verification_reasons
    assert has_action?(assessment, :collect_more_canary_volume)
    assert has_action?(assessment, :collect_more_parity_samples)
  end

  test "assess reports promotion_ready when accept streak threshold is met" do
    put_rollout!(mode: :event_based, stage: :canary)

    :ok = Reporter.record_decision(%{action: :enqueue_runtime, reason: :enabled})
    :ok = Reporter.record_parity_report(%{status: :match})
    await_rollout_counts(1, 1)

    assessment =
      JidoConversation.rollout_runbook_assess(
        verification_opts: [
          min_runtime_decisions: 1,
          min_parity_reports: 1,
          max_mismatch_rate: 1.0,
          max_legacy_unavailable_rate: 1.0,
          max_drop_rate: 1.0
        ],
        controller_opts: [require_accept_streak: 1, rollback_stage: :shadow],
        apply?: false
      )

    assert assessment.gate == :promotion_ready
    assert assessment.recommendation_action == :promote
    refute assessment.apply_attempted?
    refute assessment.applied?
    assert has_action?(assessment, :promote_rollout_stage)
  end

  test "assess reports rollback_required and trigger-specific actions" do
    put_rollout!(mode: :event_based, stage: :ramp)

    :ok = Reporter.record_decision(%{action: :enqueue_runtime, reason: :enabled})
    :ok = Reporter.record_decision(%{action: :drop, reason: :invalid_contract})
    :ok = Reporter.record_parity_report(%{status: :match})
    await_rollout_counts(1, 1)

    assessment =
      JidoConversation.rollout_runbook_assess(
        verification_opts: [
          min_runtime_decisions: 1,
          min_parity_reports: 1,
          max_mismatch_rate: 1.0,
          max_legacy_unavailable_rate: 1.0,
          max_drop_rate: 0.2
        ],
        controller_opts: [require_accept_streak: 2, rollback_stage: :shadow],
        apply?: false
      )

    assert assessment.gate == :rollback_required
    assert assessment.recommendation_action == :rollback
    assert :drop_rate_exceeded in assessment.rollback_triggers
    assert has_action?(assessment, :rollback_rollout_stage)
    assert has_action?(assessment, :investigate_drop_rate)
  end

  test "assess reports disabled gate when rollout mode is disabled" do
    put_rollout!(mode: :disabled, stage: :canary)

    assessment = JidoConversation.rollout_runbook_assess(apply?: false)

    assert assessment.gate == :disabled
    assert has_action?(assessment, :enable_shadow_mode)
    assert has_action?(assessment, :verify_canary_scope)
  end

  test "assess reports steady_state at full rollout with accepted verification" do
    put_rollout!(mode: :event_based, stage: :full)

    :ok = Reporter.record_decision(%{action: :enqueue_runtime, reason: :enabled})
    :ok = Reporter.record_parity_report(%{status: :match})
    await_rollout_counts(1, 1)

    assessment =
      JidoConversation.rollout_runbook_assess(
        verification_opts: [
          min_runtime_decisions: 1,
          min_parity_reports: 1,
          max_mismatch_rate: 1.0,
          max_legacy_unavailable_rate: 1.0,
          max_drop_rate: 1.0
        ],
        controller_opts: [require_accept_streak: 1, rollback_stage: :shadow],
        apply?: false
      )

    assert assessment.gate == :steady_state
    assert assessment.recommendation_action == :noop
    assert has_action?(assessment, :maintain_full_rollout)
    assert has_action?(assessment, :continue_slo_monitoring)
  end

  test "assess marks promotion as applied when apply is enabled" do
    put_rollout!(mode: :event_based, stage: :canary)

    :ok = Reporter.record_decision(%{action: :enqueue_runtime, reason: :enabled})
    :ok = Reporter.record_parity_report(%{status: :match})
    await_rollout_counts(1, 1)

    assessment =
      JidoConversation.rollout_runbook_assess(
        verification_opts: [
          min_runtime_decisions: 1,
          min_parity_reports: 1,
          max_mismatch_rate: 1.0,
          max_legacy_unavailable_rate: 1.0,
          max_drop_rate: 1.0
        ],
        controller_opts: [require_accept_streak: 1, rollback_stage: :shadow],
        apply?: true
      )

    assert assessment.gate == :promotion_ready
    assert assessment.apply_attempted?
    assert assessment.applied?
    assert assessment.apply_error == nil
    assert has_action?(assessment, :promotion_applied)
    assert Config.rollout_stage() == :ramp
    assert Config.rollout_mode() == :event_based
  end

  defp put_rollout!(overrides) when is_list(overrides) do
    current = Application.get_env(@app, @key, [])
    rollout = current |> Keyword.get(:rollout, []) |> Keyword.merge(overrides)
    updated = Keyword.put(current, :rollout, rollout)
    Application.put_env(@app, @key, updated)
    :ok = Config.validate!()
  end

  defp has_action?(assessment, action) do
    Enum.any?(assessment.action_items, &(&1.action == action))
  end

  defp await_rollout_counts(min_runtime_decisions, min_parity_reports, attempts \\ 100)

  defp await_rollout_counts(_min_runtime_decisions, _min_parity_reports, 0) do
    raise "condition not met within timeout"
  end

  defp await_rollout_counts(min_runtime_decisions, min_parity_reports, attempts) do
    snapshot = Reporter.snapshot()

    runtime_decision_count =
      Map.get(snapshot.decision_counts, :enqueue_runtime, 0) +
        Map.get(snapshot.decision_counts, :parity_only, 0)

    parity_report_count = Map.get(snapshot, :parity_report_count, 0)

    if runtime_decision_count >= min_runtime_decisions and
         parity_report_count >= min_parity_reports do
      :ok
    else
      Process.sleep(10)
      await_rollout_counts(min_runtime_decisions, min_parity_reports, attempts - 1)
    end
  end
end
