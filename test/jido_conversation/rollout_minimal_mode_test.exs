defmodule JidoConversation.RolloutMinimalModeTest do
  use ExUnit.Case, async: false

  alias JidoConversation.Config
  alias JidoConversation.Rollout
  alias JidoConversation.Signal.Contract

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

  test "minimal mode bypasses rollout gating and always enqueues runtime" do
    set_rollout!(
      minimal_mode: true,
      mode: :disabled,
      canary: [enabled: true, subjects: ["different-subject"], tenant_ids: [], channels: []],
      parity: [
        enabled: true,
        sample_rate: 1.0,
        max_reports: 50,
        legacy_adapter: JidoConversation.Rollout.Parity.NoopLegacyAdapter
      ]
    )

    signal =
      Contract.normalize!(%{
        type: "conv.in.message.received",
        source: "/tests/minimal_mode",
        subject: "conversation-minimal-1",
        data: %{message_id: "msg-minimal-1", ingress: "web"},
        extensions: %{"contract_major" => 1}
      })

    decision = Rollout.decide(signal)

    assert decision.mode == :event_based
    assert decision.action == :enqueue_runtime
    assert decision.reason == :minimal_mode_enabled
    assert decision.canary_match?
    refute decision.parity_sampled?
  end

  test "rollout policy remains configurable when minimal mode is disabled" do
    set_rollout!(
      minimal_mode: false,
      mode: :disabled,
      canary: [enabled: false, subjects: [], tenant_ids: [], channels: []]
    )

    signal =
      Contract.normalize!(%{
        type: "conv.in.message.received",
        source: "/tests/minimal_mode",
        subject: "conversation-minimal-2",
        data: %{message_id: "msg-minimal-2", ingress: "web"},
        extensions: %{"contract_major" => 1}
      })

    decision = Rollout.decide(signal)

    assert decision.mode == :disabled
    assert decision.action == :drop
    assert decision.reason == :rollout_disabled
  end

  defp set_rollout!(overrides) when is_list(overrides) do
    current = Application.get_env(@app, @key, [])
    rollout = current |> Keyword.get(:rollout, []) |> Keyword.merge(overrides)
    updated = Keyword.put(current, :rollout, rollout)
    Application.put_env(@app, @key, updated)
    :ok = Config.validate!()
  end
end
