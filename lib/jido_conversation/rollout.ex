defmodule JidoConversation.Rollout do
  @moduledoc """
  Rollout policy decisions for runtime migration and progressive enablement.
  """

  alias Jido.Signal
  alias JidoConversation.Config

  @type rollout_mode :: :event_based | :shadow | :disabled
  @type action :: :enqueue_runtime | :parity_only | :drop

  @type decision :: %{
          mode: rollout_mode(),
          action: action(),
          reason: atom(),
          canary_match?: boolean(),
          parity_sampled?: boolean(),
          subject: String.t() | nil,
          tenant_id: String.t() | nil,
          channel: String.t() | nil
        }

  @spec decide(Signal.t()) :: decision()
  def decide(%Signal{} = signal) do
    base = signal_scope(signal)

    if Config.rollout_minimal_mode?() do
      minimal_decision(base)
    else
      mode = Config.rollout_mode()
      canary_match? = canary_match?(signal, Config.rollout_canary())
      parity_sampled? = parity_sampled?(signal, Config.rollout_parity())

      decide_with_rollout_mode(base, mode, canary_match?, parity_sampled?)
    end
  end

  @spec canary_match?(Signal.t(), keyword()) :: boolean()
  def canary_match?(%Signal{} = signal, canary_cfg) when is_list(canary_cfg) do
    if Keyword.get(canary_cfg, :enabled, false) do
      scope = signal_scope(signal)
      subjects = MapSet.new(Keyword.get(canary_cfg, :subjects, []))
      tenant_ids = MapSet.new(Keyword.get(canary_cfg, :tenant_ids, []))
      channels = MapSet.new(Keyword.get(canary_cfg, :channels, []))

      MapSet.member?(subjects, scope.subject) or
        MapSet.member?(tenant_ids, scope.tenant_id) or
        MapSet.member?(channels, scope.channel)
    else
      true
    end
  end

  @spec parity_sampled?(Signal.t(), keyword()) :: boolean()
  def parity_sampled?(%Signal{} = signal, parity_cfg) when is_list(parity_cfg) do
    enabled? = Keyword.get(parity_cfg, :enabled, false)
    sample_rate = Keyword.get(parity_cfg, :sample_rate, 0.0)

    enabled? and sample_rate > 0 and stable_sample_match?(signal, sample_rate)
  end

  @spec stable_sample_match?(Signal.t(), float()) :: boolean()
  def stable_sample_match?(%Signal{} = signal, sample_rate)
      when is_number(sample_rate) and sample_rate >= 0 and sample_rate <= 1 do
    key = signal.id || "#{signal.type}:#{signal.subject}"
    bucket = :erlang.phash2(key, 10_000)
    ratio = bucket / 10_000
    ratio < sample_rate
  end

  @spec signal_scope(Signal.t()) :: %{
          subject: String.t() | nil,
          tenant_id: String.t() | nil,
          channel: String.t() | nil
        }
  def signal_scope(%Signal{} = signal) do
    %{
      subject: signal.subject,
      tenant_id:
        first_present([
          fetch_field(signal.extensions, :tenant_id),
          fetch_field(signal.data, :tenant_id)
        ]),
      channel:
        first_present([
          fetch_field(signal.data, :channel),
          fetch_field(signal.data, :ingress),
          fetch_field(signal.extensions, :channel)
        ])
    }
  end

  defp fetch_field(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, to_string(key))
  end

  defp fetch_field(_map, _key), do: nil

  defp first_present(values) when is_list(values) do
    Enum.find(values, &present_value?/1)
  end

  defp present_value?(value) when is_binary(value), do: String.trim(value) != ""
  defp present_value?(value), do: not is_nil(value)

  defp minimal_decision(base) do
    Map.merge(base, %{
      mode: :event_based,
      action: :enqueue_runtime,
      reason: :minimal_mode_enabled,
      canary_match?: true,
      parity_sampled?: false
    })
  end

  defp decide_with_rollout_mode(base, :disabled, _canary_match?, _parity_sampled?) do
    Map.merge(base, %{
      mode: :disabled,
      action: :drop,
      reason: :rollout_disabled,
      canary_match?: false,
      parity_sampled?: false
    })
  end

  defp decide_with_rollout_mode(base, :event_based, true, parity_sampled?) do
    Map.merge(base, %{
      mode: :event_based,
      action: :enqueue_runtime,
      reason: :enabled,
      canary_match?: true,
      parity_sampled?: parity_sampled?
    })
  end

  defp decide_with_rollout_mode(base, :event_based, false, _parity_sampled?) do
    Map.merge(base, %{
      mode: :event_based,
      action: :drop,
      reason: :canary_filtered,
      canary_match?: false,
      parity_sampled?: false
    })
  end

  defp decide_with_rollout_mode(base, :shadow, true, parity_sampled?) do
    Map.merge(base, %{
      mode: :shadow,
      action: :parity_only,
      reason: :shadow_mode,
      canary_match?: true,
      parity_sampled?: parity_sampled?
    })
  end

  defp decide_with_rollout_mode(base, :shadow, false, _parity_sampled?) do
    Map.merge(base, %{
      mode: :shadow,
      action: :drop,
      reason: :canary_filtered,
      canary_match?: false,
      parity_sampled?: false
    })
  end
end
