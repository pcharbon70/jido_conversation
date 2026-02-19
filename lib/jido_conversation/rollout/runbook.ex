defmodule JidoConversation.Rollout.Runbook do
  @moduledoc """
  Produces operator-focused rollout gate assessments and action items.
  """

  alias JidoConversation.Config
  alias JidoConversation.Rollout.Controller
  alias JidoConversation.Rollout.Manager
  alias JidoConversation.Rollout.Verification

  @rollback_triggers [
    :parity_mismatch_rate_exceeded,
    :drop_rate_exceeded,
    :legacy_unavailable_rate_exceeded
  ]

  @type gate :: :disabled | :hold | :promotion_ready | :steady_state | :rollback_required
  @type priority :: :high | :medium | :low

  @type action_item :: %{
          action: atom(),
          reason: atom(),
          priority: priority()
        }

  @type assessment :: %{
          assessed_at: DateTime.t(),
          mode: Controller.mode(),
          stage: Controller.stage(),
          verification_status: Verification.status(),
          verification_reasons: [atom()],
          recommendation_action: Controller.action(),
          next_stage: Controller.stage(),
          next_mode: :event_based | :shadow,
          accept_streak: non_neg_integer(),
          required_accept_streak: pos_integer(),
          gate: gate(),
          rollback_triggers: [atom()],
          apply_attempted?: boolean(),
          applied?: boolean(),
          apply_error: term() | nil,
          action_items: [action_item()]
        }

  @spec assess(keyword()) :: assessment()
  def assess(opts \\ []) when is_list(opts) do
    manager_cfg = Config.rollout_manager()
    apply? = Keyword.get(opts, :apply?, Keyword.get(manager_cfg, :auto_apply, false))

    evaluation = Manager.evaluate(opts)
    snapshot = Manager.snapshot()
    recommendation = evaluation.recommendation
    verification = evaluation.verification
    mode = Config.rollout_mode()
    stage = Config.rollout_stage()

    gate = gate(mode, verification.status, recommendation.action, stage)
    rollback_triggers = rollback_triggers(verification.reasons)

    %{
      assessed_at: DateTime.utc_now(),
      mode: mode,
      stage: stage,
      verification_status: verification.status,
      verification_reasons: verification.reasons,
      recommendation_action: recommendation.action,
      next_stage: recommendation.next_stage,
      next_mode: recommendation.next_mode,
      accept_streak: snapshot.accept_streak,
      required_accept_streak: recommendation.required_accept_streak,
      gate: gate,
      rollback_triggers: rollback_triggers,
      apply_attempted?: apply? and recommendation.action in [:promote, :rollback],
      applied?: evaluation.applied?,
      apply_error: evaluation.apply_error,
      action_items:
        action_items(gate, verification.reasons, rollback_triggers, evaluation.applied?)
    }
  end

  defp gate(:disabled, _verification_status, _recommendation_action, _stage), do: :disabled

  defp gate(_mode, :rollback_recommended, _recommendation_action, _stage), do: :rollback_required
  defp gate(_mode, _verification_status, :rollback, _stage), do: :rollback_required
  defp gate(_mode, _verification_status, :promote, _stage), do: :promotion_ready
  defp gate(_mode, :accept, :noop, :full), do: :steady_state
  defp gate(_mode, _verification_status, _recommendation_action, _stage), do: :hold

  defp rollback_triggers(reasons) when is_list(reasons) do
    reasons
    |> Enum.filter(&(&1 in @rollback_triggers))
    |> Enum.uniq()
  end

  defp action_items(:disabled, _reasons, _rollback_triggers, _applied?) do
    [
      %{action: :enable_shadow_mode, reason: :rollout_disabled, priority: :medium},
      %{action: :verify_canary_scope, reason: :rollout_disabled, priority: :low}
    ]
  end

  defp action_items(:steady_state, _reasons, _rollback_triggers, _applied?) do
    [
      %{action: :maintain_full_rollout, reason: :already_full_rollout, priority: :medium},
      %{action: :continue_slo_monitoring, reason: :already_full_rollout, priority: :low}
    ]
  end

  defp action_items(:promotion_ready, _reasons, _rollback_triggers, true) do
    [
      %{action: :promotion_applied, reason: :verification_accept_streak_met, priority: :medium},
      %{
        action: :monitor_post_promotion,
        reason: :verification_accept_streak_met,
        priority: :medium
      }
    ]
  end

  defp action_items(:promotion_ready, _reasons, _rollback_triggers, false) do
    [
      %{action: :promote_rollout_stage, reason: :verification_accept_streak_met, priority: :high},
      %{
        action: :monitor_post_promotion,
        reason: :verification_accept_streak_met,
        priority: :medium
      }
    ]
  end

  defp action_items(:rollback_required, reasons, rollback_triggers, true) do
    [
      %{action: :rollback_applied, reason: :verification_rollback_recommended, priority: :high},
      %{action: :open_incident, reason: :verification_rollback_recommended, priority: :high}
      | rollback_trigger_actions(rollback_triggers, reasons)
    ]
  end

  defp action_items(:rollback_required, reasons, rollback_triggers, false) do
    [
      %{
        action: :rollback_rollout_stage,
        reason: :verification_rollback_recommended,
        priority: :high
      },
      %{
        action: :consider_disabling_rollout,
        reason: :verification_rollback_recommended,
        priority: :high
      },
      %{action: :open_incident, reason: :verification_rollback_recommended, priority: :high}
      | rollback_trigger_actions(rollback_triggers, reasons)
    ]
  end

  defp action_items(:hold, reasons, _rollback_triggers, _applied?) do
    hold_actions =
      []
      |> maybe_add_action(:collect_more_canary_volume, reasons, :insufficient_runtime_decisions)
      |> maybe_add_action(:collect_more_parity_samples, reasons, :insufficient_parity_reports)

    if hold_actions == [] do
      [%{action: :continue_monitoring, reason: :verification_hold, priority: :medium}]
    else
      hold_actions
    end
  end

  defp rollback_trigger_actions(rollback_triggers, reasons) do
    []
    |> maybe_add_action(
      :investigate_parity_mismatch,
      rollback_triggers,
      :parity_mismatch_rate_exceeded
    )
    |> maybe_add_action(:investigate_drop_rate, rollback_triggers, :drop_rate_exceeded)
    |> maybe_add_action(
      :investigate_legacy_unavailable,
      rollback_triggers,
      :legacy_unavailable_rate_exceeded
    )
    |> Enum.map(fn action ->
      reason = action.reason
      priority = if reason in reasons, do: :high, else: :medium
      %{action | priority: priority}
    end)
  end

  defp maybe_add_action(actions, action, reasons, reason) do
    if reason in reasons do
      actions ++ [%{action: action, reason: reason, priority: :medium}]
    else
      actions
    end
  end
end
