defmodule Jido.Conversation.Signal.Supervisor do
  @moduledoc """
  Supervises signal infrastructure required by the conversation runtime.
  """

  use Supervisor

  alias Jido.Conversation.Config

  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      {Jido.Signal.Bus, Config.bus_options()}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
