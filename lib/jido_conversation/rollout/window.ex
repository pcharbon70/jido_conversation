defmodule JidoConversation.Rollout.Window do
  @moduledoc """
  Computes post-rollout verification window acceptance checks from recent assessments.
  """

  alias JidoConversation.Config
  alias JidoConversation.Rollout.Controller
  alias JidoConversation.Rollout.Manager
  alias JidoConversation.Rollout.Runbook

  @type status :: :insufficient_data | :monitor | :accepted | :rejected
  @type priority :: :high | :medium | :low

  @type metrics :: %{
          assessment_count: non_neg_integer(),
          accept_count: non_neg_integer(),
          hold_count: non_neg_integer(),
          rollback_count: non_neg_integer(),
          applied_transition_count: non_neg_integer()
        }

  @type thresholds :: %{
          window_minutes: pos_integer(),
          min_assessments: pos_integer(),
          required_accept_count: pos_integer(),
          max_rollback_count: non_neg_integer()
        }

  @type action_item :: %{
          action: atom(),
          reason: atom(),
          priority: priority()
        }

  @type assessment :: %{
          assessed_at: DateTime.t(),
          status: status(),
          thresholds: thresholds(),
          metrics: metrics(),
          window_started_at: DateTime.t() | nil,
          window_ended_at: DateTime.t() | nil,
          latest_gate: Runbook.gate(),
          latest_stage: Controller.stage(),
          latest_mode: Controller.mode(),
          latest_runbook_assessment: Runbook.assessment(),
          action_items: [action_item()]
        }

  @spec assess(keyword()) :: assessment()
  def assess(opts \\ []) when is_list(opts) do
    thresholds = resolve_thresholds(opts)
    runbook_assessment = Runbook.assess(opts)
    manager_snapshot = Manager.snapshot()

    recent_results =
      window_recent_results(manager_snapshot.recent_results, thresholds.window_minutes)

    metrics = derive_metrics(recent_results)
    status = derive_status(metrics, thresholds)
    {window_started_at, window_ended_at} = derive_window_bounds(recent_results)

    %{
      assessed_at: DateTime.utc_now(),
      status: status,
      thresholds: thresholds,
      metrics: metrics,
      window_started_at: window_started_at,
      window_ended_at: window_ended_at,
      latest_gate: runbook_assessment.gate,
      latest_stage: runbook_assessment.stage,
      latest_mode: runbook_assessment.mode,
      latest_runbook_assessment: runbook_assessment,
      action_items: action_items(status)
    }
  end

  defp resolve_thresholds(opts) when is_list(opts) do
    cfg = Config.rollout_window()

    %{
      window_minutes: Keyword.get(opts, :window_minutes, Keyword.fetch!(cfg, :window_minutes)),
      min_assessments: Keyword.get(opts, :min_assessments, Keyword.fetch!(cfg, :min_assessments)),
      required_accept_count:
        Keyword.get(opts, :required_accept_count, Keyword.fetch!(cfg, :required_accept_count)),
      max_rollback_count:
        Keyword.get(opts, :max_rollback_count, Keyword.fetch!(cfg, :max_rollback_count))
    }
  end

  defp window_recent_results(results, window_minutes) when is_list(results) do
    cutoff = DateTime.utc_now() |> DateTime.add(-window_minutes * 60, :second)

    Enum.filter(results, fn result ->
      DateTime.compare(result.evaluated_at, cutoff) in [:eq, :gt]
    end)
  end

  defp derive_metrics(results) when is_list(results) do
    %{
      assessment_count: length(results),
      accept_count: count_by_verification(results, :accept),
      hold_count: count_by_verification(results, :hold),
      rollback_count: count_rollback(results),
      applied_transition_count: Enum.count(results, & &1.applied?)
    }
  end

  defp derive_status(metrics, thresholds) do
    cond do
      metrics.assessment_count < thresholds.min_assessments ->
        :insufficient_data

      metrics.rollback_count > thresholds.max_rollback_count ->
        :rejected

      metrics.accept_count >= thresholds.required_accept_count ->
        :accepted

      true ->
        :monitor
    end
  end

  defp derive_window_bounds([]), do: {nil, nil}

  defp derive_window_bounds(results) when is_list(results) do
    started_at =
      results
      |> Enum.map(& &1.evaluated_at)
      |> Enum.min(DateTime)

    ended_at =
      results
      |> Enum.map(& &1.evaluated_at)
      |> Enum.max(DateTime)

    {started_at, ended_at}
  end

  defp count_by_verification(results, status) do
    Enum.count(results, fn result ->
      result.verification.status == status
    end)
  end

  defp count_rollback(results) do
    Enum.count(results, fn result ->
      result.verification.status == :rollback_recommended or
        result.recommendation.action == :rollback
    end)
  end

  defp action_items(:insufficient_data) do
    [
      %{
        action: :collect_more_window_observations,
        reason: :insufficient_assessments,
        priority: :medium
      }
    ]
  end

  defp action_items(:monitor) do
    [%{action: :continue_window_monitoring, reason: :window_not_yet_accepted, priority: :medium}]
  end

  defp action_items(:accepted) do
    [
      %{action: :mark_window_accepted, reason: :acceptance_window_passed, priority: :medium},
      %{
        action: :continue_post_rollout_observability,
        reason: :acceptance_window_passed,
        priority: :low
      }
    ]
  end

  defp action_items(:rejected) do
    [
      %{action: :execute_rollback_runbook, reason: :acceptance_window_failed, priority: :high},
      %{action: :open_incident, reason: :acceptance_window_failed, priority: :high}
    ]
  end
end
