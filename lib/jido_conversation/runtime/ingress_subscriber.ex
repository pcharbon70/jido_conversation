defmodule JidoConversation.Runtime.IngressSubscriber do
  @moduledoc """
  Subscribes to conversation signals and forwards them to runtime partitions.
  """

  use GenServer

  require Logger

  alias Jido.Signal.Bus
  alias JidoConversation.Config
  alias JidoConversation.Runtime.Coordinator
  alias JidoConversation.Signal.Contract

  @retry_ms 1_000

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    state = %{subscription_id: nil}
    {:ok, state, {:continue, :subscribe}}
  end

  @impl true
  def handle_continue(:subscribe, state) do
    {:noreply, subscribe(state)}
  end

  @impl true
  def handle_info(:retry_subscribe, state) do
    {:noreply, subscribe(state)}
  end

  @impl true
  def handle_info({:signal, signal}, state) do
    case Contract.normalize(signal) do
      {:ok, normalized} ->
        Coordinator.enqueue(normalized)

      {:error, reason} ->
        Logger.warning("dropping contract-invalid signal: #{inspect(reason)}")
    end

    {:noreply, state}
  end

  @impl true
  def terminate(_reason, %{subscription_id: nil}), do: :ok

  def terminate(_reason, %{subscription_id: subscription_id}) do
    bus_name = Config.bus_name()
    _ = Bus.unsubscribe(bus_name, subscription_id)
    :ok
  end

  defp subscribe(state) do
    bus_name = Config.bus_name()
    pattern = Config.subscription_pattern()
    opts = Config.persistent_subscription_options(self())

    case Bus.subscribe(bus_name, pattern, opts) do
      {:ok, subscription_id} ->
        Logger.info("runtime ingress subscriber connected pattern=#{pattern}")
        %{state | subscription_id: subscription_id}

      {:error, reason} ->
        Logger.warning("runtime ingress subscriber failed, retrying: #{inspect(reason)}")
        Process.send_after(self(), :retry_subscribe, @retry_ms)
        state
    end
  end
end
