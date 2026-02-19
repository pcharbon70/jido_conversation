defmodule JidoConversation.Runtime.IngressSubscriber do
  @moduledoc """
  Subscribes to conversation signals and forwards them to runtime partitions.
  """

  use GenServer

  require Logger

  alias Jido.Signal
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
  def handle_info({:signal, {signal_log_id, signal}}, %{subscription_id: subscription_id} = state) do
    process_signal(signal)
    ack_signal_log_id(subscription_id, signal_log_id)

    {:noreply, state}
  end

  @impl true
  def handle_info({:signal, signal}, %{subscription_id: subscription_id} = state) do
    process_signal(signal)
    ack_signal(subscription_id, signal)
    {:noreply, state}
  end

  defp process_signal(%Signal{type: <<"conv.applied.", _::binary>>}), do: :ok

  defp process_signal(signal) do
    case Contract.normalize(signal) do
      {:ok, normalized} ->
        Coordinator.enqueue(normalized)

      {:error, reason} ->
        Logger.warning("dropping contract-invalid signal: #{inspect(reason)}")
    end
  end

  defp ack_signal(nil, _signal), do: :ok

  defp ack_signal(subscription_id, %Signal{id: signal_id}) when is_binary(signal_id) do
    case resolve_signal_log_id(subscription_id, signal_id) do
      {:ok, signal_log_id} -> ack_signal_log_id(subscription_id, signal_log_id)
      :error -> :ok
    end
  end

  defp ack_signal(_subscription_id, _signal), do: :ok

  defp resolve_signal_log_id(subscription_id, signal_id) do
    with {:ok, bus_pid} <- Bus.whereis(Config.bus_name()),
         bus_state <- :sys.get_state(bus_pid),
         subscriptions when is_map(subscriptions) <- Map.get(bus_state, :subscriptions),
         subscription when not is_nil(subscription) <- Map.get(subscriptions, subscription_id),
         persistence_pid when is_pid(persistence_pid) <- Map.get(subscription, :persistence_pid),
         true <- Process.alive?(persistence_pid),
         persistence_state <- :sys.get_state(persistence_pid),
         in_flight when is_map(in_flight) <- Map.get(persistence_state, :in_flight_signals),
         {signal_log_id, _signal} <-
           Enum.find(in_flight, fn {_signal_log_id, in_flight_signal} ->
             in_flight_signal.id == signal_id
           end) do
      {:ok, signal_log_id}
    else
      _ -> :error
    end
  end

  defp ack_signal_log_id(nil, _signal_log_id), do: :ok

  defp ack_signal_log_id(subscription_id, signal_log_id) do
    case Bus.ack(Config.bus_name(), subscription_id, signal_log_id) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.warning(
          "failed to ack signal_log_id=#{inspect(signal_log_id)}: #{inspect(reason)}"
        )
    end
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
