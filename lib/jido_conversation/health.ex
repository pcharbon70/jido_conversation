defmodule JidoConversation.Health do
  @moduledoc """
  Lightweight health snapshot for runtime boot validation and diagnostics.
  """

  alias JidoConversation.Config

  @type status_map :: %{
          status: :ok | :degraded,
          bus_name: atom(),
          bus_alive?: boolean(),
          runtime_supervisor_alive?: boolean(),
          runtime_coordinator_alive?: boolean()
        }

  @spec status() :: status_map()
  def status do
    bus_name = Config.bus_name()

    bus_pid = Process.whereis(bus_name)
    runtime_supervisor = Process.whereis(JidoConversation.Runtime.Supervisor)
    coordinator = Process.whereis(JidoConversation.Runtime.Coordinator)

    status =
      if is_pid(bus_pid) and is_pid(runtime_supervisor) and is_pid(coordinator) do
        :ok
      else
        :degraded
      end

    %{
      status: status,
      bus_name: bus_name,
      bus_alive?: is_pid(bus_pid),
      runtime_supervisor_alive?: is_pid(runtime_supervisor),
      runtime_coordinator_alive?: is_pid(coordinator)
    }
  end
end
