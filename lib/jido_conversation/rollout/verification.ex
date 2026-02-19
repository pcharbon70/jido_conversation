defmodule JidoConversation.Rollout.Verification do
  @moduledoc """
  Computes rollout acceptance verdicts from rollout snapshots and thresholds.
  """

  alias JidoConversation.Config
  alias JidoConversation.Rollout.Reporter

  @type status :: :accept | :hold | :rollback_recommended

  @type metrics :: %{
          runtime_decision_count: non_neg_integer(),
          total_decision_count: non_neg_integer(),
          enqueue_runtime_count: non_neg_integer(),
          parity_only_count: non_neg_integer(),
          drop_count: non_neg_integer(),
          drop_rate: float(),
          parity_report_count: non_neg_integer(),
          mismatch_count: non_neg_integer(),
          mismatch_rate: float(),
          legacy_unavailable_count: non_neg_integer(),
          legacy_unavailable_rate: float(),
          parity_match_count: non_neg_integer()
        }

  @type thresholds :: %{
          min_runtime_decisions: pos_integer(),
          min_parity_reports: pos_integer(),
          max_mismatch_rate: float(),
          max_legacy_unavailable_rate: float(),
          max_drop_rate: float()
        }

  @type report :: %{
          status: status(),
          acceptance_passed?: boolean(),
          checked_at: DateTime.t(),
          reasons: [atom()],
          metrics: metrics(),
          thresholds: thresholds()
        }

  @spec evaluate(Reporter.snapshot(), keyword()) :: report()
  def evaluate(snapshot \\ Reporter.snapshot(), opts \\ [])
      when is_map(snapshot) and is_list(opts) do
    thresholds = resolve_thresholds(opts)
    metrics = derive_metrics(snapshot)
    {status, reasons} = derive_status(metrics, thresholds)

    %{
      status: status,
      acceptance_passed?: status == :accept,
      checked_at: DateTime.utc_now(),
      reasons: reasons,
      metrics: metrics,
      thresholds: thresholds
    }
  end

  defp resolve_thresholds(opts) when is_list(opts) do
    cfg = Config.rollout_verification()

    %{
      min_runtime_decisions:
        Keyword.get(opts, :min_runtime_decisions, Keyword.fetch!(cfg, :min_runtime_decisions)),
      min_parity_reports:
        Keyword.get(opts, :min_parity_reports, Keyword.fetch!(cfg, :min_parity_reports)),
      max_mismatch_rate:
        Keyword.get(opts, :max_mismatch_rate, Keyword.fetch!(cfg, :max_mismatch_rate)),
      max_legacy_unavailable_rate:
        Keyword.get(
          opts,
          :max_legacy_unavailable_rate,
          Keyword.fetch!(cfg, :max_legacy_unavailable_rate)
        ),
      max_drop_rate: Keyword.get(opts, :max_drop_rate, Keyword.fetch!(cfg, :max_drop_rate))
    }
  end

  defp derive_metrics(snapshot) when is_map(snapshot) do
    decision_counts = Map.get(snapshot, :decision_counts, %{})
    enqueue_runtime_count = Map.get(decision_counts, :enqueue_runtime, 0)
    parity_only_count = Map.get(decision_counts, :parity_only, 0)
    drop_count = Map.get(decision_counts, :drop, 0)
    runtime_decision_count = enqueue_runtime_count + parity_only_count
    total_decision_count = runtime_decision_count + drop_count
    drop_rate = ratio(drop_count, total_decision_count)

    parity_report_count = Map.get(snapshot, :parity_report_count, 0)
    parity_status_counts = parity_status_counts(snapshot)
    mismatch_count = Map.get(parity_status_counts, :mismatch, 0)
    legacy_unavailable_count = Map.get(parity_status_counts, :legacy_unavailable, 0)
    parity_match_count = Map.get(parity_status_counts, :match, 0)

    %{
      runtime_decision_count: runtime_decision_count,
      total_decision_count: total_decision_count,
      enqueue_runtime_count: enqueue_runtime_count,
      parity_only_count: parity_only_count,
      drop_count: drop_count,
      drop_rate: drop_rate,
      parity_report_count: parity_report_count,
      mismatch_count: mismatch_count,
      mismatch_rate: ratio(mismatch_count, parity_report_count),
      legacy_unavailable_count: legacy_unavailable_count,
      legacy_unavailable_rate: ratio(legacy_unavailable_count, parity_report_count),
      parity_match_count: parity_match_count
    }
  end

  defp derive_status(metrics, thresholds) do
    hold_reasons =
      []
      |> maybe_add_reason(
        metrics.runtime_decision_count < thresholds.min_runtime_decisions,
        :insufficient_runtime_decisions
      )
      |> maybe_add_reason(
        metrics.parity_report_count < thresholds.min_parity_reports,
        :insufficient_parity_reports
      )
      |> maybe_add_reason(
        metrics.legacy_unavailable_rate > thresholds.max_legacy_unavailable_rate,
        :legacy_unavailable_rate_exceeded
      )

    rollback_reasons =
      []
      |> maybe_add_reason(
        metrics.mismatch_rate > thresholds.max_mismatch_rate,
        :parity_mismatch_rate_exceeded
      )
      |> maybe_add_reason(metrics.drop_rate > thresholds.max_drop_rate, :drop_rate_exceeded)

    cond do
      rollback_reasons != [] ->
        {:rollback_recommended, rollback_reasons ++ hold_reasons}

      hold_reasons != [] ->
        {:hold, hold_reasons}

      true ->
        {:accept, []}
    end
  end

  defp parity_status_counts(snapshot) do
    from_snapshot = Map.get(snapshot, :parity_status_counts)

    if is_map(from_snapshot) do
      normalize_parity_status_counts(from_snapshot)
    else
      snapshot
      |> Map.get(:recent_parity_reports, [])
      |> Enum.reduce(%{match: 0, mismatch: 0, legacy_unavailable: 0}, fn report, acc ->
        status = Map.get(report, :status) || Map.get(report, "status")
        increment_status_count(acc, status)
      end)
    end
  end

  defp normalize_parity_status_counts(counts) do
    %{
      match: Map.get(counts, :match, 0) + Map.get(counts, "match", 0),
      mismatch: Map.get(counts, :mismatch, 0) + Map.get(counts, "mismatch", 0),
      legacy_unavailable:
        Map.get(counts, :legacy_unavailable, 0) + Map.get(counts, "legacy_unavailable", 0)
    }
  end

  defp increment_status_count(counts, :match), do: Map.update!(counts, :match, &(&1 + 1))

  defp increment_status_count(counts, :mismatch), do: Map.update!(counts, :mismatch, &(&1 + 1))

  defp increment_status_count(counts, :legacy_unavailable),
    do: Map.update!(counts, :legacy_unavailable, &(&1 + 1))

  defp increment_status_count(counts, _status), do: counts

  defp ratio(_numerator, 0), do: 0.0

  defp ratio(numerator, denominator) when is_integer(numerator) and is_integer(denominator) do
    numerator / denominator
  end

  defp maybe_add_reason(reasons, true, reason), do: reasons ++ [reason]
  defp maybe_add_reason(reasons, false, _reason), do: reasons
end
