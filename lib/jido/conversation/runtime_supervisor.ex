defmodule Jido.Conversation.RuntimeSupervisor do
  @moduledoc """
  Supervises the process registry and dynamic server supervisor used by
  `Jido.Conversation.Runtime`.
  """

  use Supervisor

  @registry_name Jido.Conversation.Registry
  @server_supervisor_name Jido.Conversation.ServerSupervisor

  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts \\ []) when is_list(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      {Registry, keys: :unique, name: @registry_name},
      {DynamicSupervisor, strategy: :one_for_one, name: @server_supervisor_name}
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end
end
