defmodule JidoConversation.Rollout.Controller do
  @moduledoc """
  Computes rollout stage/mode transition recommendations from verification reports.
  """

  alias JidoConversation.Config
  alias JidoConversation.Rollout.Verification

  @type stage :: :shadow | :canary | :ramp | :full
  @type mode :: :event_based | :shadow | :disabled
  @type action :: :promote | :hold | :rollback | :noop

  @type recommendation :: %{
          action: action(),
          reason: atom(),
          current_stage: stage(),
          next_stage: stage(),
          current_mode: mode(),
          next_mode: :event_based | :shadow,
          verification_status: Verification.status(),
          required_accept_streak: pos_integer(),
          previous_accept_streak: non_neg_integer(),
          next_accept_streak: non_neg_integer()
        }

  @ordered_stages [:shadow, :canary, :ramp, :full]

  @spec recommend(Verification.report(), keyword()) :: recommendation()
  def recommend(verification_report, opts \\ [])
      when is_map(verification_report) and is_list(opts) do
    current_stage = Keyword.get(opts, :stage, Config.rollout_stage())
    current_mode = Keyword.get(opts, :mode, Config.rollout_mode())
    controller_cfg = Config.rollout_controller()

    required_accept_streak =
      Keyword.get(opts, :require_accept_streak, controller_cfg[:require_accept_streak])

    rollback_stage = Keyword.get(opts, :rollback_stage, controller_cfg[:rollback_stage])
    previous_accept_streak = Keyword.get(opts, :accept_streak, 0)
    verification_status = Map.get(verification_report, :status, :hold)

    validate_stage!(current_stage, :stage)
    validate_stage!(rollback_stage, :rollback_stage)
    validate_mode!(current_mode, :mode)
    validate_required_accept_streak!(required_accept_streak)
    validate_accept_streak!(previous_accept_streak)

    base = %{
      current_stage: current_stage,
      current_mode: current_mode,
      verification_status: verification_status,
      required_accept_streak: required_accept_streak,
      previous_accept_streak: previous_accept_streak
    }

    case verification_status do
      :rollback_recommended ->
        build_recommendation(base, %{
          action: :rollback,
          reason: :verification_rollback_recommended,
          next_stage: rollback_stage,
          next_mode: stage_mode(rollback_stage),
          next_accept_streak: 0
        })

      :hold ->
        build_recommendation(base, %{
          action: :hold,
          reason: :verification_hold,
          next_stage: current_stage,
          next_mode: stage_mode(current_stage),
          next_accept_streak: 0
        })

      :accept ->
        accept_streak = previous_accept_streak + 1

        cond do
          accept_streak < required_accept_streak ->
            build_recommendation(base, %{
              action: :hold,
              reason: :awaiting_accept_streak,
              next_stage: current_stage,
              next_mode: stage_mode(current_stage),
              next_accept_streak: accept_streak
            })

          next_stage(current_stage) == nil ->
            build_recommendation(base, %{
              action: :noop,
              reason: :already_full_rollout,
              next_stage: current_stage,
              next_mode: stage_mode(current_stage),
              next_accept_streak: accept_streak
            })

          true ->
            promoted_stage = next_stage(current_stage)

            build_recommendation(base, %{
              action: :promote,
              reason: :verification_accept_streak_met,
              next_stage: promoted_stage,
              next_mode: stage_mode(promoted_stage),
              next_accept_streak: 0
            })
        end

      _other ->
        build_recommendation(base, %{
          action: :hold,
          reason: :unknown_verification_status,
          next_stage: current_stage,
          next_mode: stage_mode(current_stage),
          next_accept_streak: 0
        })
    end
  end

  @spec apply_recommendation(keyword(), recommendation()) :: keyword()
  def apply_recommendation(rollout_config, recommendation)
      when is_list(rollout_config) and is_map(recommendation) do
    rollout_config
    |> Keyword.put(:stage, recommendation.next_stage)
    |> Keyword.put(:mode, recommendation.next_mode)
  end

  @spec stage_mode(stage()) :: :event_based | :shadow
  def stage_mode(:shadow), do: :shadow
  def stage_mode(stage) when stage in [:canary, :ramp, :full], do: :event_based

  @spec next_stage(stage()) :: stage() | nil
  def next_stage(stage) when stage in @ordered_stages do
    case Enum.find_index(@ordered_stages, &(&1 == stage)) do
      nil ->
        nil

      index ->
        Enum.at(@ordered_stages, index + 1)
    end
  end

  defp build_recommendation(base, attrs) when is_map(base) and is_map(attrs),
    do: Map.merge(base, attrs)

  defp validate_stage!(stage, _field) when stage in @ordered_stages, do: :ok

  defp validate_stage!(stage, field) do
    raise ArgumentError, "expected #{field} rollout stage, got: #{inspect(stage)}"
  end

  defp validate_mode!(mode, _field) when mode in [:event_based, :shadow, :disabled], do: :ok

  defp validate_mode!(mode, field) do
    raise ArgumentError, "expected #{field} rollout mode, got: #{inspect(mode)}"
  end

  defp validate_required_accept_streak!(value) when is_integer(value) and value > 0, do: :ok

  defp validate_required_accept_streak!(value) do
    raise ArgumentError,
          "expected require_accept_streak to be positive integer, got: #{inspect(value)}"
  end

  defp validate_accept_streak!(value) when is_integer(value) and value >= 0, do: :ok

  defp validate_accept_streak!(value) do
    raise ArgumentError,
          "expected accept_streak to be non-negative integer, got: #{inspect(value)}"
  end
end
