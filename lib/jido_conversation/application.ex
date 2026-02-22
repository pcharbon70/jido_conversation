defmodule Jido.Conversation.Application do
  @moduledoc false

  use Application

  alias Jido.Conversation.Config
  alias Jido.Conversation.Ingest.Pipeline, as: IngestPipeline
  alias Jido.Conversation.Runtime.Supervisor, as: RuntimeSupervisor
  alias Jido.Conversation.Signal.Supervisor, as: SignalSupervisor
  alias Jido.Conversation.Telemetry

  @impl true
  def start(_type, _args) do
    Config.validate!()

    children = [
      Telemetry,
      SignalSupervisor,
      IngestPipeline,
      RuntimeSupervisor
    ]

    opts = [strategy: :one_for_one, name: Jido.Conversation.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
