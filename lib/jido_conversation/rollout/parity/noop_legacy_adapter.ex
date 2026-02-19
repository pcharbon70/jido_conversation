defmodule JidoConversation.Rollout.Parity.NoopLegacyAdapter do
  @moduledoc """
  Default parity adapter used when no legacy runtime adapter is configured.
  """

  @behaviour JidoConversation.Rollout.ParityAdapter

  @impl true
  def outputs_for_conversation(_conversation_id, _opts) do
    {:error, :legacy_adapter_not_configured}
  end
end
