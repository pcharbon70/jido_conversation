defmodule JidoConversation.Rollout.ParityAdapter do
  @moduledoc """
  Behaviour for parity comparison against a legacy/alternate runtime.
  """

  @type output_item :: map() | Jido.Signal.t()

  @callback outputs_for_conversation(String.t(), keyword()) ::
              {:ok, [output_item()]} | {:error, term()}
end
