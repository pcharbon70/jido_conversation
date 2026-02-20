defmodule JidoConversation.Rollout.Settings do
  @moduledoc """
  Runtime rollout settings controls for operators.
  """

  alias JidoConversation.Config
  alias JidoConversation.Rollout.Controller

  @app :jido_conversation
  @key JidoConversation.EventSystem

  @type mode :: Controller.mode()
  @type stage :: Controller.stage()

  @type snapshot :: %{
          minimal_mode: boolean(),
          mode: mode(),
          stage: stage(),
          rollout: keyword()
        }

  @type update_error ::
          :minimal_mode_enabled
          | {:invalid_config, String.t()}
          | {:invalid_config, term()}

  @spec snapshot() :: snapshot()
  def snapshot do
    rollout = Config.rollout()

    %{
      minimal_mode: Keyword.fetch!(rollout, :minimal_mode),
      mode: Keyword.fetch!(rollout, :mode),
      stage: Keyword.fetch!(rollout, :stage),
      rollout: rollout
    }
  end

  @spec set_minimal_mode(boolean(), keyword()) :: {:ok, snapshot()} | {:error, update_error()}
  def set_minimal_mode(enabled, opts \\ []) when is_boolean(enabled) and is_list(opts) do
    apply_overrides([minimal_mode: enabled], opts)
  end

  @spec set_mode(mode()) :: {:ok, snapshot()} | {:error, update_error()}
  def set_mode(mode) when mode in [:event_based, :shadow, :disabled] do
    if Config.rollout_minimal_mode?() and mode != :event_based do
      {:error, :minimal_mode_enabled}
    else
      apply_overrides([mode: mode], force_event_based: false)
    end
  end

  @spec set_stage(stage()) :: {:ok, snapshot()} | {:error, update_error()}
  def set_stage(stage) when stage in [:shadow, :canary, :ramp, :full] do
    apply_overrides([stage: stage], force_event_based: false)
  end

  @spec configure(keyword(), keyword()) :: {:ok, snapshot()} | {:error, update_error()}
  def configure(rollout_overrides, opts \\ [])
      when is_list(rollout_overrides) and is_list(opts) do
    apply_overrides(rollout_overrides, opts)
  end

  defp apply_overrides(rollout_overrides, opts)
       when is_list(rollout_overrides) and is_list(opts) do
    existing_event_system = Application.get_env(@app, @key, [])

    existing_rollout =
      existing_event_system
      |> Keyword.get(:rollout, [])

    updated_rollout =
      existing_rollout
      |> Keyword.merge(rollout_overrides)
      |> maybe_force_event_based(opts)

    updated_event_system = Keyword.put(existing_event_system, :rollout, updated_rollout)

    try do
      Application.put_env(@app, @key, updated_event_system)
      Config.validate!()
      {:ok, snapshot()}
    rescue
      error ->
        Application.put_env(@app, @key, existing_event_system)
        {:error, {:invalid_config, Exception.message(error)}}
    catch
      kind, reason ->
        Application.put_env(@app, @key, existing_event_system)
        {:error, {:invalid_config, {kind, reason}}}
    end
  end

  defp maybe_force_event_based(rollout, opts) do
    minimal_mode = Keyword.get(rollout, :minimal_mode, false)
    force_event_based = Keyword.get(opts, :force_event_based, true)

    if minimal_mode and force_event_based do
      Keyword.put(rollout, :mode, :event_based)
    else
      rollout
    end
  end
end
