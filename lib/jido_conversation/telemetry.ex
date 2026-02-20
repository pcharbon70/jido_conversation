defmodule JidoConversation.Telemetry do
  @moduledoc """
  Attaches telemetry handlers and aggregates runtime operational metrics.
  """

  use GenServer

  alias JidoConversation.Config

  @type latency_summary :: %{
          count: non_neg_integer(),
          avg_ms: float(),
          min_ms: float() | nil,
          max_ms: float() | nil
        }

  @type metrics_snapshot :: %{
          queue_depth: %{
            total: non_neg_integer(),
            by_partition: %{integer() => non_neg_integer()}
          },
          apply_latency_ms: latency_summary(),
          abort_latency_ms: latency_summary(),
          retry_count: non_neg_integer(),
          dlq_count: non_neg_integer(),
          dispatch_failure_count: non_neg_integer(),
          last_dispatch_failure: map() | nil
        }

  @type state :: %{
          events: [list(atom())],
          queue_depth_by_partition: %{integer() => non_neg_integer()},
          apply_latency_us: latency_state(),
          abort_latency_us: latency_state(),
          retry_count: non_neg_integer(),
          dlq_count: non_neg_integer(),
          dispatch_failure_count: non_neg_integer(),
          last_dispatch_failure: map() | nil
        }

  @typep latency_state :: %{
           count: non_neg_integer(),
           total_us: non_neg_integer(),
           min_us: non_neg_integer() | nil,
           max_us: non_neg_integer() | nil
         }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec snapshot() :: metrics_snapshot()
  def snapshot do
    GenServer.call(__MODULE__, :snapshot)
  end

  @spec reset() :: :ok
  def reset do
    GenServer.call(__MODULE__, :reset)
  end

  @impl true
  def init(_opts) do
    events =
      Config.telemetry_events()
      |> Enum.uniq()

    Enum.each(events, fn event ->
      case :telemetry.attach(handler_id(event), event, &__MODULE__.handle_event/4, %{}) do
        :ok -> :ok
        {:error, :already_exists} -> :ok
      end
    end)

    {:ok, new_state(events)}
  end

  @impl true
  def terminate(_reason, %{events: events}) do
    Enum.each(events, fn event ->
      :telemetry.detach(handler_id(event))
    end)

    :ok
  end

  @impl true
  def handle_call(:snapshot, _from, state) do
    {:reply, to_snapshot(state), state}
  end

  @impl true
  def handle_call(:reset, _from, state) do
    {:reply, :ok, new_state(state.events)}
  end

  @impl true
  def handle_cast({:telemetry_event, event_name, measurements, metadata}, state) do
    {:noreply, update_state(state, event_name, measurements, metadata)}
  end

  @doc false
  def handle_event(event_name, measurements, metadata, _config) do
    GenServer.cast(__MODULE__, {:telemetry_event, event_name, measurements, metadata})
    :ok
  end

  defp new_state(events) do
    %{
      events: events,
      queue_depth_by_partition: %{},
      apply_latency_us: new_latency_state(),
      abort_latency_us: new_latency_state(),
      retry_count: 0,
      dlq_count: 0,
      dispatch_failure_count: 0,
      last_dispatch_failure: nil
    }
  end

  defp new_latency_state do
    %{count: 0, total_us: 0, min_us: nil, max_us: nil}
  end

  defp update_state(
         state,
         [:jido_conversation, :runtime, :queue, :depth],
         %{depth: depth},
         metadata
       ) do
    partition_id = metadata[:partition_id]

    if is_integer(partition_id) do
      queue_depth_by_partition =
        Map.put(state.queue_depth_by_partition, partition_id, normalize_non_neg_int(depth))

      %{state | queue_depth_by_partition: queue_depth_by_partition}
    else
      state
    end
  end

  defp update_state(
         state,
         [:jido_conversation, :runtime, :apply, :stop],
         %{duration_us: duration_us},
         _metadata
       ) do
    %{state | apply_latency_us: update_latency(state.apply_latency_us, duration_us)}
  end

  defp update_state(
         state,
         [:jido_conversation, :runtime, :abort, :latency],
         %{duration_us: duration_us},
         _metadata
       ) do
    %{state | abort_latency_us: update_latency(state.abort_latency_us, duration_us)}
  end

  defp update_state(
         state,
         [:jido, :signal, :subscription, :dispatch, :retry],
         _measurements,
         _metadata
       ) do
    %{state | retry_count: state.retry_count + 1}
  end

  defp update_state(state, [:jido, :signal, :subscription, :dlq], _measurements, _metadata) do
    %{state | dlq_count: state.dlq_count + 1}
  end

  defp update_state(
         state,
         [:jido, :signal, :bus, :dispatch_error],
         measurements,
         metadata
       ) do
    last_dispatch_failure = %{
      bus_name: metadata[:bus_name],
      signal_id: metadata[:signal_id],
      signal_type: metadata[:signal_type],
      subscription_id: metadata[:subscription_id],
      error: metadata[:error],
      at_timestamp: measurements[:timestamp]
    }

    %{
      state
      | dispatch_failure_count: state.dispatch_failure_count + 1,
        last_dispatch_failure: last_dispatch_failure
    }
  end

  defp update_state(state, _event_name, _measurements, _metadata), do: state

  defp normalize_non_neg_int(value) when is_integer(value) and value >= 0, do: value
  defp normalize_non_neg_int(value) when is_float(value) and value >= 0, do: trunc(value)
  defp normalize_non_neg_int(_value), do: 0

  defp update_latency(latency_state, duration_us) do
    duration_us = normalize_non_neg_int(duration_us)

    %{
      count: latency_state.count + 1,
      total_us: latency_state.total_us + duration_us,
      min_us: min_or_default(latency_state.min_us, duration_us),
      max_us: max_or_default(latency_state.max_us, duration_us)
    }
  end

  defp min_or_default(nil, value), do: value
  defp min_or_default(current, value), do: min(current, value)

  defp max_or_default(nil, value), do: value
  defp max_or_default(current, value), do: max(current, value)

  defp to_snapshot(state) do
    %{
      queue_depth: %{
        total: state.queue_depth_by_partition |> Map.values() |> Enum.sum(),
        by_partition: state.queue_depth_by_partition
      },
      apply_latency_ms: latency_summary(state.apply_latency_us),
      abort_latency_ms: latency_summary(state.abort_latency_us),
      retry_count: state.retry_count,
      dlq_count: state.dlq_count,
      dispatch_failure_count: state.dispatch_failure_count,
      last_dispatch_failure: state.last_dispatch_failure
    }
  end

  defp latency_summary(%{count: 0}) do
    %{count: 0, avg_ms: 0.0, min_ms: nil, max_ms: nil}
  end

  defp latency_summary(%{count: count, total_us: total_us, min_us: min_us, max_us: max_us}) do
    %{
      count: count,
      avg_ms: us_to_ms(total_us / count),
      min_ms: us_to_ms(min_us),
      max_ms: us_to_ms(max_us)
    }
  end

  defp us_to_ms(nil), do: nil
  defp us_to_ms(value) when is_integer(value), do: value / 1_000
  defp us_to_ms(value) when is_float(value), do: Float.round(value / 1_000, 3)

  defp handler_id(event_name), do: {__MODULE__, event_name}
end
