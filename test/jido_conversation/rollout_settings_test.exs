defmodule JidoConversation.RolloutSettingsTest do
  use ExUnit.Case, async: false

  alias JidoConversation.Config

  @app :jido_conversation
  @key JidoConversation.EventSystem

  setup do
    original_cfg = Application.get_env(@app, @key, [])

    on_exit(fn ->
      Application.put_env(@app, @key, original_cfg)
      :ok = Config.validate!()
    end)

    :ok
  end

  test "rollout_settings_snapshot returns rollout mode, stage, and minimal mode" do
    snapshot = JidoConversation.rollout_settings_snapshot()

    assert snapshot.mode in [:event_based, :shadow, :disabled]
    assert snapshot.stage in [:shadow, :canary, :ramp, :full]
    assert is_boolean(snapshot.minimal_mode)
    assert is_list(snapshot.rollout)
  end

  test "rollout_set_minimal_mode(true) forces mode to event_based by default" do
    set_rollout!(minimal_mode: false, mode: :disabled)

    assert {:ok, snapshot} = JidoConversation.rollout_set_minimal_mode(true)
    assert snapshot.minimal_mode
    assert snapshot.mode == :event_based
    assert Config.rollout_mode() == :event_based
  end

  test "rollout_set_mode rejects non-event_based mode while minimal mode is enabled" do
    set_rollout!(minimal_mode: true, mode: :event_based)

    assert {:error, :minimal_mode_enabled} = JidoConversation.rollout_set_mode(:shadow)
    assert Config.rollout_mode() == :event_based
  end

  test "rollout_set_mode works after disabling minimal mode" do
    set_rollout!(minimal_mode: true, mode: :event_based)

    assert {:ok, disabled} = JidoConversation.rollout_set_minimal_mode(false)
    refute disabled.minimal_mode

    assert {:ok, snapshot} = JidoConversation.rollout_set_mode(:shadow)
    assert snapshot.mode == :shadow
    refute snapshot.minimal_mode
    assert Config.rollout_mode() == :shadow
  end

  test "rollout_set_stage updates stage with validation" do
    set_rollout!(minimal_mode: false, mode: :event_based, stage: :canary)

    assert {:ok, snapshot} = JidoConversation.rollout_set_stage(:ramp)
    assert snapshot.stage == :ramp
    assert snapshot.mode == :event_based
    assert Config.rollout_stage() == :ramp
  end

  test "rollout_configure reverts on invalid rollout override" do
    set_rollout!(minimal_mode: false, mode: :event_based, stage: :canary)
    before_snapshot = JidoConversation.rollout_settings_snapshot()

    assert {:error, {:invalid_config, _reason}} =
             JidoConversation.rollout_configure(canary: :invalid)

    after_snapshot = JidoConversation.rollout_settings_snapshot()
    assert after_snapshot.rollout == before_snapshot.rollout
    assert Config.rollout_stage() == before_snapshot.stage
    assert Config.rollout_mode() == before_snapshot.mode
  end

  defp set_rollout!(overrides) when is_list(overrides) do
    current = Application.get_env(@app, @key, [])
    rollout = current |> Keyword.get(:rollout, []) |> Keyword.merge(overrides)
    updated = Keyword.put(current, :rollout, rollout)
    Application.put_env(@app, @key, updated)
    :ok = Config.validate!()
  end
end
