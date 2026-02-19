defmodule JidoConversation.Telemetry do
  @moduledoc """
  Attaches telemetry handlers for selected Jido Signal events.
  """

  use GenServer

  require Logger

  alias JidoConversation.Config

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    events = Config.telemetry_events()

    Enum.each(events, fn event ->
      :ok = :telemetry.attach(handler_id(event), event, &__MODULE__.handle_event/4, %{})
    end)

    {:ok, %{events: events}}
  end

  @impl true
  def terminate(_reason, %{events: events}) do
    Enum.each(events, fn event ->
      :telemetry.detach(handler_id(event))
    end)

    :ok
  end

  @doc false
  def handle_event(event_name, measurements, metadata, _config) do
    Logger.debug(fn ->
      "telemetry event=#{inspect(event_name)} measurements=#{inspect(measurements)} metadata=#{inspect(Map.take(metadata, [:bus_name, :signal_id, :signal_type, :subscription_id]))}"
    end)
  end

  defp handler_id(event_name), do: {__MODULE__, event_name}
end
