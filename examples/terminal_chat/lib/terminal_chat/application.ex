defmodule TerminalChat.Application do
  @moduledoc """
  Supervision tree for the standalone terminal chat example.
  """

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Task.Supervisor, name: TerminalChat.TaskSupervisor},
      TerminalChat.Session
    ]

    opts = [strategy: :one_for_one, name: TerminalChat.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
