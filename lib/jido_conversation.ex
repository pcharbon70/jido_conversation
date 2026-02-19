defmodule JidoConversation do
  @moduledoc """
  Entry points for the conversation runtime.
  """

  alias JidoConversation.Health

  @doc """
  Returns runtime health details for the signal bus and runtime supervisors.
  """
  @spec health() :: Health.status_map()
  def health do
    Health.status()
  end
end
