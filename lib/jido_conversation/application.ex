defmodule JidoConversation.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    JidoConversation.Config.validate!()

    children = [
      JidoConversation.Telemetry,
      JidoConversation.Rollout.Reporter,
      JidoConversation.Signal.Supervisor,
      JidoConversation.Ingest.Pipeline,
      JidoConversation.Runtime.Supervisor
    ]

    opts = [strategy: :one_for_one, name: JidoConversation.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
