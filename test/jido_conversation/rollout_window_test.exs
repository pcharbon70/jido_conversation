defmodule JidoConversation.RolloutWindowTest do
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

  test "rollout_window_assess reports insufficient_data when minimum assessments are not met" do
    put_rollout!(mode: :event_based, stage: :canary)

    :ok = Reporter.record_decision(%{action: :enqueue_runtime, reason: :enabled})
    :ok = Reporter.record_parity_report(%{status: :match})
    await_rollout_counts(1, 1)

    _ = accepted_assessment(apply?: false)

    assessment =
      JidoConversation.rollout_window_assess(
        verification_opts: accepted_verification_opts(),
        controller_opts: [require_accept_streak: 1, rollback_stage: :shadow],
        min_assessments: 3,
        required_accept_count: 2,
        max_rollback_count: 0,
        apply?: false
      )

    assert assessment.status == :insufficient_data
    assert assessment.metrics.assessment_count == 2
    assert has_action?(assessment, :collect_more_window_observations)
  end

  test "rollout_window_assess reports accepted when acceptance thresholds pass" do
    put_rollout!(mode: :event_based, stage: :canary)

    :ok = Reporter.record_decision(%{action: :enqueue_runtime, reason: :enabled})
    :ok = Reporter.record_parity_report(%{status: :match})
    await_rollout_counts(1, 1)

    _ = accepted_assessment(apply?: false)
    _ = accepted_assessment(apply?: false)

    assessment =
      JidoConversation.rollout_window_assess(
        verification_opts: accepted_verification_opts(),
        controller_opts: [require_accept_streak: 1, rollback_stage: :shadow],
        min_assessments: 3,
        required_accept_count: 3,
        max_rollback_count: 0,
        apply?: false
      )

    assert assessment.status == :accepted
    assert assessment.metrics.assessment_count == 3
    assert assessment.metrics.accept_count == 3
    assert assessment.metrics.rollback_count == 0
    assert has_action?(assessment, :mark_window_accepted)
    assert has_action?(assessment, :continue_post_rollout_observability)
  end

  test "rollout_window_assess reports rejected when rollback count exceeds threshold" do
    put_rollout!(mode: :event_based, stage: :ramp)

    :ok = Reporter.record_decision(%{action: :enqueue_runtime, reason: :enabled})
    :ok = Reporter.record_decision(%{action: :drop, reason: :invalid_contract})
    :ok = Reporter.record_parity_report(%{status: :match})
    await_rollout_counts(1, 1)

    _ =
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

    assessment =
      JidoConversation.rollout_window_assess(
        verification_opts: [
          min_runtime_decisions: 1,
          min_parity_reports: 1,
          max_mismatch_rate: 1.0,
          max_legacy_unavailable_rate: 1.0,
          max_drop_rate: 0.2
        ],
        controller_opts: [require_accept_streak: 2, rollback_stage: :shadow],
        min_assessments: 2,
        required_accept_count: 1,
        max_rollback_count: 0,
        apply?: false
      )

    assert assessment.status == :rejected
    assert assessment.metrics.rollback_count >= 1
    assert assessment.latest_runbook_assessment.gate == :rollback_required
    assert has_action?(assessment, :execute_rollback_runbook)
    assert has_action?(assessment, :open_incident)
  end

  test "rollout_window_assess reports monitor when thresholds are partially met without rollback" do
    put_rollout!(mode: :event_based, stage: :canary)

    :ok = Reporter.record_decision(%{action: :enqueue_runtime, reason: :enabled})
    :ok = Reporter.record_parity_report(%{status: :match})
    await_rollout_counts(1, 1)

    _ = accepted_assessment(apply?: false)
    _ = accepted_assessment(apply?: false)

    assessment =
      JidoConversation.rollout_window_assess(
        verification_opts: accepted_verification_opts(),
        controller_opts: [require_accept_streak: 1, rollback_stage: :shadow],
        min_assessments: 3,
        required_accept_count: 4,
        max_rollback_count: 0,
        apply?: false
      )

    assert assessment.status == :monitor
    assert assessment.metrics.assessment_count == 3
    assert assessment.metrics.accept_count == 3
    assert has_action?(assessment, :continue_window_monitoring)
  end

  defp accepted_assessment(opts) do
    JidoConversation.rollout_runbook_assess(
      Keyword.merge(
        [
          verification_opts: accepted_verification_opts(),
          controller_opts: [require_accept_streak: 1, rollback_stage: :shadow]
        ],
        opts
      )
    )
  end

  defp accepted_verification_opts do
    [
      min_runtime_decisions: 1,
      min_parity_reports: 1,
      max_mismatch_rate: 1.0,
      max_legacy_unavailable_rate: 1.0,
      max_drop_rate: 1.0
    ]
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
