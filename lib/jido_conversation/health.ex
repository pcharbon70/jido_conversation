defmodule Jido.Conversation.Health do
  @moduledoc """
  Lightweight health snapshot for runtime boot validation and diagnostics.
  """

  alias Jido.Conversation.Config
  alias Jido.Signal.Bus

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

    bus_alive? =
      case Bus.whereis(bus_name) do
        {:ok, bus_pid} when is_pid(bus_pid) -> true
        _other -> false
      end

    runtime_supervisor = Process.whereis(Jido.Conversation.Runtime.Supervisor)
    coordinator = Process.whereis(Jido.Conversation.Runtime.Coordinator)

    status =
      if bus_alive? and is_pid(runtime_supervisor) and is_pid(coordinator) do
        :ok
      else
        :degraded
      end

    %{
      status: status,
      bus_name: bus_name,
      bus_alive?: bus_alive?,
      runtime_supervisor_alive?: is_pid(runtime_supervisor),
      runtime_coordinator_alive?: is_pid(coordinator)
    }
  end
end
