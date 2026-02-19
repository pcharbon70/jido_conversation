defmodule JidoConversation.RolloutVerificationTest do
  use ExUnit.Case, async: false

  alias JidoConversation.Rollout.Reporter
  alias JidoConversation.Rollout.Verification

  setup do
    :ok = Reporter.reset()
    :ok
  end

  test "accepts when rollout and parity metrics are within thresholds" do
    snapshot = %{
      decision_counts: %{enqueue_runtime: 90, parity_only: 10, drop: 5},
      reason_counts: %{},
      parity_sample_count: 12,
      parity_report_count: 40,
      parity_status_counts: %{match: 36, mismatch: 2, legacy_unavailable: 2},
      recent_parity_samples: [],
      recent_parity_reports: []
    }

    report =
      Verification.evaluate(snapshot,
        min_runtime_decisions: 25,
        min_parity_reports: 10,
        max_mismatch_rate: 0.1,
        max_legacy_unavailable_rate: 0.1,
        max_drop_rate: 0.2
      )

    assert report.status == :accept
    assert report.acceptance_passed?
    assert report.reasons == []
    assert report.metrics.runtime_decision_count == 100
    assert report.metrics.drop_count == 5
  end

  test "holds when minimum rollout/parity volume is not met" do
    snapshot = %{
      decision_counts: %{enqueue_runtime: 2, parity_only: 0, drop: 1},
      reason_counts: %{},
      parity_sample_count: 1,
      parity_report_count: 1,
      parity_status_counts: %{match: 1, mismatch: 0, legacy_unavailable: 0},
      recent_parity_samples: [],
      recent_parity_reports: []
    }

    report =
      Verification.evaluate(snapshot,
        min_runtime_decisions: 10,
        min_parity_reports: 5,
        max_mismatch_rate: 0.5,
        max_legacy_unavailable_rate: 0.5,
        max_drop_rate: 0.9
      )

    assert report.status == :hold
    assert :insufficient_runtime_decisions in report.reasons
    assert :insufficient_parity_reports in report.reasons
  end

  test "recommends rollback when parity mismatch rate breaches threshold" do
    snapshot = %{
      decision_counts: %{enqueue_runtime: 30, parity_only: 0, drop: 1},
      reason_counts: %{},
      parity_sample_count: 20,
      parity_report_count: 20,
      parity_status_counts: %{match: 10, mismatch: 10, legacy_unavailable: 0},
      recent_parity_samples: [],
      recent_parity_reports: []
    }

    report =
      Verification.evaluate(snapshot,
        min_runtime_decisions: 10,
        min_parity_reports: 10,
        max_mismatch_rate: 0.2,
        max_legacy_unavailable_rate: 0.2,
        max_drop_rate: 0.9
      )

    assert report.status == :rollback_recommended
    assert :parity_mismatch_rate_exceeded in report.reasons
  end

  test "recommends rollback when drop rate breaches threshold" do
    snapshot = %{
      decision_counts: %{enqueue_runtime: 20, parity_only: 0, drop: 15},
      reason_counts: %{},
      parity_sample_count: 12,
      parity_report_count: 12,
      parity_status_counts: %{match: 12, mismatch: 0, legacy_unavailable: 0},
      recent_parity_samples: [],
      recent_parity_reports: []
    }

    report =
      Verification.evaluate(snapshot,
        min_runtime_decisions: 10,
        min_parity_reports: 10,
        max_mismatch_rate: 0.5,
        max_legacy_unavailable_rate: 0.5,
        max_drop_rate: 0.2
      )

    assert report.status == :rollback_recommended
    assert :drop_rate_exceeded in report.reasons
  end

  test "derives parity status counts from recent reports when aggregate counts are missing" do
    snapshot = %{
      decision_counts: %{enqueue_runtime: 5, parity_only: 0, drop: 0},
      reason_counts: %{},
      parity_sample_count: 3,
      parity_report_count: 3,
      recent_parity_samples: [],
      recent_parity_reports: [
        %{status: :match},
        %{status: :mismatch},
        %{status: :legacy_unavailable}
      ]
    }

    report =
      Verification.evaluate(snapshot,
        min_runtime_decisions: 1,
        min_parity_reports: 1,
        max_mismatch_rate: 1.0,
        max_legacy_unavailable_rate: 1.0,
        max_drop_rate: 1.0
      )

    assert report.status == :accept
    assert report.metrics.parity_match_count == 1
    assert report.metrics.mismatch_count == 1
    assert report.metrics.legacy_unavailable_count == 1
  end

  test "rollout_verify reads reporter state and returns acceptance report" do
    :ok = Reporter.record_decision(%{action: :enqueue_runtime, reason: :enabled})
    :ok = Reporter.record_parity_report(%{status: :match})

    report =
      eventually(fn ->
        current =
          JidoConversation.rollout_verify(
            min_runtime_decisions: 1,
            min_parity_reports: 1,
            max_mismatch_rate: 0.5,
            max_legacy_unavailable_rate: 0.5,
            max_drop_rate: 0.5
          )

        if current.metrics.runtime_decision_count >= 1 and
             current.metrics.parity_report_count >= 1 do
          {:ok, current}
        else
          :retry
        end
      end)

    assert report.status == :accept
    assert report.metrics.parity_match_count == 1
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
