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
    mode = Config.rollout_mode()
    canary_match? = canary_match?(signal, Config.rollout_canary())
    parity_sampled? = parity_sampled?(signal, Config.rollout_parity())

    base = signal_scope(signal)

    case mode do
      :disabled ->
        Map.merge(base, %{
          mode: mode,
          action: :drop,
          reason: :rollout_disabled,
          canary_match?: false,
          parity_sampled?: false
        })

      :event_based ->
        if canary_match? do
          Map.merge(base, %{
            mode: mode,
            action: :enqueue_runtime,
            reason: :enabled,
            canary_match?: true,
            parity_sampled?: parity_sampled?
          })
        else
          Map.merge(base, %{
            mode: mode,
            action: :drop,
            reason: :canary_filtered,
            canary_match?: false,
            parity_sampled?: false
          })
        end

      :shadow ->
        if canary_match? do
          Map.merge(base, %{
            mode: mode,
            action: :parity_only,
            reason: :shadow_mode,
            canary_match?: true,
            parity_sampled?: parity_sampled?
          })
        else
          Map.merge(base, %{
            mode: mode,
            action: :drop,
            reason: :canary_filtered,
            canary_match?: false,
            parity_sampled?: false
          })
        end
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
end
