defmodule JidoConversation.RolloutControllerTest do
  use ExUnit.Case, async: false

  alias JidoConversation.Rollout.Controller
  alias JidoConversation.Rollout.Reporter

  setup do
    :ok = Reporter.reset()
    :ok
  end

  test "holds until required accept streak is reached" do
    recommendation =
      Controller.recommend(
        %{status: :accept},
        stage: :canary,
        mode: :event_based,
        require_accept_streak: 2,
        accept_streak: 0
      )

    assert recommendation.action == :hold
    assert recommendation.reason == :awaiting_accept_streak
    assert recommendation.next_stage == :canary
    assert recommendation.next_mode == :event_based
    assert recommendation.next_accept_streak == 1
  end

  test "promotes stage once accept streak threshold is met" do
    recommendation =
      Controller.recommend(
        %{status: :accept},
        stage: :canary,
        mode: :event_based,
        require_accept_streak: 2,
        accept_streak: 1
      )

    assert recommendation.action == :promote
    assert recommendation.reason == :verification_accept_streak_met
    assert recommendation.current_stage == :canary
    assert recommendation.next_stage == :ramp
    assert recommendation.next_mode == :event_based
    assert recommendation.next_accept_streak == 0
  end

  test "recommends rollback to configured stage when verification requests rollback" do
    recommendation =
      Controller.recommend(
        %{status: :rollback_recommended},
        stage: :ramp,
        mode: :event_based,
        require_accept_streak: 2,
        accept_streak: 1,
        rollback_stage: :shadow
      )

    assert recommendation.action == :rollback
    assert recommendation.reason == :verification_rollback_recommended
    assert recommendation.current_stage == :ramp
    assert recommendation.next_stage == :shadow
    assert recommendation.next_mode == :shadow
    assert recommendation.next_accept_streak == 0
  end

  test "returns noop at full rollout stage once accepted" do
    recommendation =
      Controller.recommend(
        %{status: :accept},
        stage: :full,
        mode: :event_based,
        require_accept_streak: 1,
        accept_streak: 0
      )

    assert recommendation.action == :noop
    assert recommendation.reason == :already_full_rollout
    assert recommendation.next_stage == :full
    assert recommendation.next_mode == :event_based
  end

  test "apply_recommendation updates rollout stage and mode" do
    rollout_cfg = [mode: :event_based, stage: :canary, controller: [require_accept_streak: 2]]

    recommendation =
      Controller.recommend(
        %{status: :rollback_recommended},
        stage: :canary,
        mode: :event_based,
        require_accept_streak: 2,
        accept_streak: 1,
        rollback_stage: :shadow
      )

    updated = Controller.apply_recommendation(rollout_cfg, recommendation)

    assert updated[:stage] == :shadow
    assert updated[:mode] == :shadow
  end

  test "rollout_recommend combines verification and controller recommendation" do
    :ok = Reporter.record_decision(%{action: :enqueue_runtime, reason: :enabled})
    :ok = Reporter.record_parity_report(%{status: :match})

    result =
      eventually(fn ->
        current =
          JidoConversation.rollout_recommend(
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
              require_accept_streak: 1,
              accept_streak: 0,
              rollback_stage: :shadow
            ]
          )

        if current.verification.metrics.runtime_decision_count >= 1 and
             current.verification.metrics.parity_report_count >= 1 do
          {:ok, current}
        else
          :retry
        end
      end)

    assert result.verification.status == :accept
    assert result.recommendation.action == :promote
    assert result.recommendation.next_stage == :ramp
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
