defmodule Jido.Conversation.Runtime.Supervisor do
  @moduledoc """
  Supervises runtime schedulers and workers that consume conversation signals.
  """

  use Supervisor

  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      {Registry, keys: :unique, name: Jido.Conversation.Runtime.Registry},
      {DynamicSupervisor,
       strategy: :one_for_one, name: Jido.Conversation.Runtime.PartitionSupervisor},
      {DynamicSupervisor,
       strategy: :one_for_one, name: Jido.Conversation.Runtime.EffectSupervisor},
      Jido.Conversation.Runtime.EffectManager,
      Jido.Conversation.Runtime.Coordinator,
      Jido.Conversation.Runtime.IngressSubscriber
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
