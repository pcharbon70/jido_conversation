defmodule Jido.Conversation.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    Jido.Conversation.Config.validate!()

    children = [
      Jido.Conversation.Telemetry,
      Jido.Conversation.Signal.Supervisor,
      Jido.Conversation.Ingest.Pipeline,
      Jido.Conversation.Runtime.Supervisor,
      Jido.Conversation.RuntimeSupervisor
    ]

    opts = [strategy: :one_for_one, name: Jido.Conversation.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
