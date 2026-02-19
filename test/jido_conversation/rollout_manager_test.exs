defmodule JidoConversation.RolloutManagerTest do
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
      :ok = Reporter.reset()
      :ok = Manager.reset()
    end)

    :ok
  end

  test "rollout_evaluate updates manager streak/history without applying config changes" do
    :ok = Reporter.record_decision(%{action: :enqueue_runtime, reason: :enabled})
    :ok = Reporter.record_parity_report(%{status: :match})
    await_rollout_counts(1, 1)

    result =
      JidoConversation.rollout_evaluate(
        verification_opts: [
          min_runtime_decisions: 1,
          min_parity_reports: 1,
          max_mismatch_rate: 1.0,
          max_legacy_unavailable_rate: 1.0,
          max_drop_rate: 1.0
        ],
        controller_opts: [
          stage: :canary,
          mode: :event_based,
          require_accept_streak: 2,
          rollback_stage: :shadow
        ],
        apply?: false
      )

    assert result.verification.status == :accept
    assert result.recommendation.action == :hold
    assert result.recommendation.next_accept_streak == 1
    refute result.applied?
    assert result.apply_error == nil

    snapshot = JidoConversation.rollout_manager_snapshot()
    assert snapshot.accept_streak == 1
    assert snapshot.evaluation_count == 1
    assert snapshot.applied_count == 0
    assert length(snapshot.recent_results) == 1
    assert snapshot.last_result.recommendation.action == :hold
  end

  test "rollout_evaluate applies promotion recommendation when apply is enabled" do
    put_rollout_config(:canary, :event_based)

    :ok = Reporter.record_decision(%{action: :enqueue_runtime, reason: :enabled})
    :ok = Reporter.record_parity_report(%{status: :match})
    await_rollout_counts(1, 1)

    result =
      JidoConversation.rollout_evaluate(
        verification_opts: [
          min_runtime_decisions: 1,
          min_parity_reports: 1,
          max_mismatch_rate: 1.0,
          max_legacy_unavailable_rate: 1.0,
          max_drop_rate: 1.0
        ],
        controller_opts: [require_accept_streak: 2, rollback_stage: :shadow],
        accept_streak: 1,
        apply?: true
      )

    assert result.recommendation.action == :promote
    assert result.recommendation.next_stage == :ramp
    assert result.applied?
    assert result.apply_error == nil

    assert Config.rollout_stage() == :ramp
    assert Config.rollout_mode() == :event_based

    snapshot = JidoConversation.rollout_manager_snapshot()
    assert snapshot.current_stage == :ramp
    assert snapshot.current_mode == :event_based
    assert snapshot.accept_streak == 0
    assert snapshot.evaluation_count == 1
    assert snapshot.applied_count == 1
  end

  test "rollout_evaluate applies rollback recommendation when thresholds fail" do
    put_rollout_config(:ramp, :event_based)

    :ok = Reporter.record_decision(%{action: :enqueue_runtime, reason: :enabled})
    :ok = Reporter.record_decision(%{action: :drop, reason: :invalid_contract})
    :ok = Reporter.record_parity_report(%{status: :match})
    await_rollout_counts(1, 1)

    result =
      JidoConversation.rollout_evaluate(
        verification_opts: [
          min_runtime_decisions: 1,
          min_parity_reports: 1,
          max_mismatch_rate: 1.0,
          max_legacy_unavailable_rate: 1.0,
          max_drop_rate: 0.2
        ],
        controller_opts: [require_accept_streak: 2, rollback_stage: :shadow],
        apply?: true
      )

    assert result.verification.status == :rollback_recommended
    assert result.recommendation.action == :rollback
    assert result.recommendation.next_stage == :shadow
    assert result.applied?
    assert result.apply_error == nil

    assert Config.rollout_stage() == :shadow
    assert Config.rollout_mode() == :shadow

    snapshot = JidoConversation.rollout_manager_snapshot()
    assert snapshot.current_stage == :shadow
    assert snapshot.current_mode == :shadow
    assert snapshot.accept_streak == 0
    assert snapshot.evaluation_count == 1
    assert snapshot.applied_count == 1
  end

  test "rollout_manager_reset clears manager streak and history" do
    :ok = Reporter.record_decision(%{action: :enqueue_runtime, reason: :enabled})
    :ok = Reporter.record_parity_report(%{status: :match})
    await_rollout_counts(1, 1)

    _ =
      JidoConversation.rollout_evaluate(
        verification_opts: [
          min_runtime_decisions: 1,
          min_parity_reports: 1,
          max_mismatch_rate: 1.0,
          max_legacy_unavailable_rate: 1.0,
          max_drop_rate: 1.0
        ],
        apply?: false
      )

    pre_reset = JidoConversation.rollout_manager_snapshot()
    assert pre_reset.evaluation_count == 1
    assert pre_reset.last_result != nil
    assert pre_reset.recent_results != []

    :ok = JidoConversation.rollout_manager_reset()

    post_reset = JidoConversation.rollout_manager_snapshot()
    assert post_reset.accept_streak == 0
    assert post_reset.last_result == nil
    assert post_reset.recent_results == []
    assert post_reset.evaluation_count == 0
    assert post_reset.applied_count == 0
  end

  defp put_rollout_config(stage, mode) do
    current = Application.get_env(@app, @key, [])
    rollout = current |> Keyword.get(:rollout, []) |> Keyword.merge(stage: stage, mode: mode)

    Application.put_env(@app, @key, Keyword.put(current, :rollout, rollout))
    :ok = Config.validate!()
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
