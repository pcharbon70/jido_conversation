defmodule Jido.Conversation.Telemetry do
  @moduledoc """
  Attaches telemetry handlers and aggregates runtime operational metrics.
  """

  use GenServer

  alias Jido.Conversation.Config

  @type latency_summary :: %{
          count: non_neg_integer(),
          avg_ms: float(),
          min_ms: float() | nil,
          max_ms: float() | nil
        }

  @type llm_lifecycle_counts :: %{
          started: non_neg_integer(),
          progress: non_neg_integer(),
          completed: non_neg_integer(),
          failed: non_neg_integer(),
          canceled: non_neg_integer()
        }

  @type llm_snapshot :: %{
          lifecycle_counts: llm_lifecycle_counts(),
          lifecycle_by_backend: %{String.t() => llm_lifecycle_counts()},
          cancel_latency_ms: latency_summary(),
          stream_duration_ms: latency_summary(),
          stream_chunks: %{
            delta: non_neg_integer(),
            thinking: non_neg_integer(),
            total: non_neg_integer()
          },
          retry_by_category: %{String.t() => non_neg_integer()},
          cancel_results: %{String.t() => non_neg_integer()}
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
          last_dispatch_failure: map() | nil,
          llm: llm_snapshot()
        }

  @type state :: %{
          events: [list(atom())],
          queue_depth_by_partition: %{integer() => non_neg_integer()},
          apply_latency_us: latency_state(),
          abort_latency_us: latency_state(),
          retry_count: non_neg_integer(),
          dlq_count: non_neg_integer(),
          dispatch_failure_count: non_neg_integer(),
          last_dispatch_failure: map() | nil,
          llm_lifecycle_counts: llm_lifecycle_counts(),
          llm_lifecycle_by_backend: %{String.t() => llm_lifecycle_counts()},
          llm_cancel_latency_us: latency_state(),
          llm_stream_duration_us: latency_state(),
          llm_stream_chunks: %{
            delta: non_neg_integer(),
            thinking: non_neg_integer(),
            total: non_neg_integer()
          },
          llm_retry_by_category: %{String.t() => non_neg_integer()},
          llm_cancel_results: %{String.t() => non_neg_integer()},
          llm_streams: %{String.t() => llm_stream_state()}
        }

  @typep latency_state :: %{
           count: non_neg_integer(),
           total_us: non_neg_integer(),
           min_us: non_neg_integer() | nil,
           max_us: non_neg_integer() | nil
         }

  @typep llm_stream_state :: %{
           started_us: non_neg_integer(),
           delta_chunks: non_neg_integer(),
           thinking_chunks: non_neg_integer(),
           backend: String.t(),
           provider: String.t() | nil,
           model: String.t() | nil
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
      last_dispatch_failure: nil,
      llm_lifecycle_counts: new_llm_lifecycle_counts(),
      llm_lifecycle_by_backend: %{},
      llm_cancel_latency_us: new_latency_state(),
      llm_stream_duration_us: new_latency_state(),
      llm_stream_chunks: %{delta: 0, thinking: 0, total: 0},
      llm_retry_by_category: %{},
      llm_cancel_results: %{},
      llm_streams: %{}
    }
  end

  defp new_latency_state do
    %{count: 0, total_us: 0, min_us: nil, max_us: nil}
  end

  defp new_llm_lifecycle_counts do
    %{started: 0, progress: 0, completed: 0, failed: 0, canceled: 0}
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
         [:jido_conversation, :runtime, :llm, :lifecycle],
         measurements,
         metadata
       ) do
    lifecycle = normalize_lifecycle(metadata[:lifecycle])
    backend = normalize_dimension(metadata[:backend], "unknown")

    effect_id =
      normalize_effect_id(metadata[:effect_id], metadata[:conversation_id], metadata[:attempt])

    started_us = normalize_non_neg_int(measurements[:timestamp_us])

    if is_nil(lifecycle) do
      state
    else
      state
      |> increment_llm_lifecycle(lifecycle)
      |> increment_llm_backend_lifecycle(backend, lifecycle)
      |> track_llm_stream_event(effect_id, lifecycle, started_us, metadata, backend)
      |> maybe_increment_llm_cancel_result(metadata)
    end
  end

  defp update_state(
         state,
         [:jido_conversation, :runtime, :llm, :cancel],
         %{duration_us: duration_us},
         metadata
       ) do
    state
    |> Map.put(:llm_cancel_latency_us, update_latency(state.llm_cancel_latency_us, duration_us))
    |> maybe_increment_llm_cancel_result(metadata)
  end

  defp update_state(
         state,
         [:jido_conversation, :runtime, :llm, :retry],
         _measurements,
         metadata
       ) do
    maybe_increment_llm_retry_category(state, metadata)
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

  defp increment_llm_lifecycle(state, lifecycle) do
    counts = Map.update!(state.llm_lifecycle_counts, lifecycle, &(&1 + 1))
    %{state | llm_lifecycle_counts: counts}
  end

  defp increment_llm_backend_lifecycle(state, backend, lifecycle) do
    lifecycle_counts =
      state.llm_lifecycle_by_backend
      |> Map.get(backend, new_llm_lifecycle_counts())
      |> Map.update!(lifecycle, &(&1 + 1))

    %{
      state
      | llm_lifecycle_by_backend:
          Map.put(state.llm_lifecycle_by_backend, backend, lifecycle_counts)
    }
  end

  defp track_llm_stream_event(state, nil, _lifecycle, _timestamp_us, _metadata, _backend),
    do: state

  defp track_llm_stream_event(state, effect_id, lifecycle, timestamp_us, metadata, backend)
       when is_binary(effect_id) do
    stream_state =
      state.llm_streams
      |> Map.get(effect_id, new_llm_stream_state(timestamp_us, backend, metadata))
      |> merge_llm_stream_dimensions(metadata, backend)
      |> increment_llm_stream_chunks(metadata)

    stream_state =
      if lifecycle == :started and timestamp_us > 0 do
        %{stream_state | started_us: timestamp_us}
      else
        stream_state
      end

    state = %{state | llm_streams: Map.put(state.llm_streams, effect_id, stream_state)}

    if terminal_lifecycle?(lifecycle) do
      finalize_llm_stream(state, effect_id, timestamp_us)
    else
      state
    end
  end

  defp new_llm_stream_state(started_us, backend, metadata) do
    %{
      started_us: max(started_us, 0),
      delta_chunks: 0,
      thinking_chunks: 0,
      backend: backend,
      provider: normalize_dimension(metadata[:provider], nil),
      model: normalize_dimension(metadata[:model], nil)
    }
  end

  defp merge_llm_stream_dimensions(stream_state, metadata, backend) do
    provider = normalize_dimension(metadata[:provider], stream_state.provider)
    model = normalize_dimension(metadata[:model], stream_state.model)

    %{
      stream_state
      | backend: normalize_dimension(metadata[:backend], backend),
        provider: provider,
        model: model
    }
  end

  defp increment_llm_stream_chunks(stream_state, metadata) do
    delta_inc = if truthy?(metadata[:token_delta?]), do: 1, else: 0
    thinking_inc = if truthy?(metadata[:thinking_delta?]), do: 1, else: 0

    %{
      stream_state
      | delta_chunks: stream_state.delta_chunks + delta_inc,
        thinking_chunks: stream_state.thinking_chunks + thinking_inc
    }
  end

  defp finalize_llm_stream(state, effect_id, timestamp_us) do
    case Map.pop(state.llm_streams, effect_id) do
      {nil, streams} ->
        %{state | llm_streams: streams}

      {stream_state, streams} ->
        duration_us = max(timestamp_us - stream_state.started_us, 0)

        llm_stream_chunks = %{
          delta: state.llm_stream_chunks.delta + stream_state.delta_chunks,
          thinking: state.llm_stream_chunks.thinking + stream_state.thinking_chunks,
          total:
            state.llm_stream_chunks.total + stream_state.delta_chunks +
              stream_state.thinking_chunks
        }

        %{
          state
          | llm_streams: streams,
            llm_stream_duration_us: update_latency(state.llm_stream_duration_us, duration_us),
            llm_stream_chunks: llm_stream_chunks
        }
    end
  end

  defp maybe_increment_llm_cancel_result(state, metadata) do
    cancel_result =
      normalize_dimension(
        metadata[:cancel_result] || metadata[:backend_cancel],
        nil
      )

    if is_binary(cancel_result) do
      %{
        state
        | llm_cancel_results: increment_string_counter(state.llm_cancel_results, cancel_result)
      }
    else
      state
    end
  end

  defp maybe_increment_llm_retry_category(state, metadata) do
    retry_category =
      normalize_dimension(
        metadata[:retry_category] || metadata[:error_category],
        nil
      )

    if is_binary(retry_category) do
      %{
        state
        | llm_retry_by_category:
            increment_string_counter(state.llm_retry_by_category, retry_category)
      }
    else
      state
    end
  end

  defp increment_string_counter(counter_map, key) when is_map(counter_map) and is_binary(key) do
    Map.update(counter_map, key, 1, &(&1 + 1))
  end

  defp normalize_lifecycle(value)
       when value in [:started, :progress, :completed, :failed, :canceled],
       do: value

  defp normalize_lifecycle(value) when is_binary(value) do
    case String.downcase(String.trim(value)) do
      "started" -> :started
      "progress" -> :progress
      "completed" -> :completed
      "failed" -> :failed
      "canceled" -> :canceled
      _ -> nil
    end
  end

  defp normalize_lifecycle(_), do: nil

  defp terminal_lifecycle?(lifecycle) when lifecycle in [:completed, :failed, :canceled], do: true
  defp terminal_lifecycle?(_lifecycle), do: false

  defp normalize_dimension(nil, default), do: default
  defp normalize_dimension(value, _default) when is_atom(value), do: Atom.to_string(value)

  defp normalize_dimension(value, default) when is_binary(value) do
    case String.trim(value) do
      "" -> default
      normalized -> normalized
    end
  end

  defp normalize_dimension(value, _default) when is_integer(value), do: Integer.to_string(value)
  defp normalize_dimension(value, _default) when is_float(value), do: Float.to_string(value)
  defp normalize_dimension(_value, default), do: default

  defp normalize_effect_id(effect_id, _conversation_id, _attempt) when is_binary(effect_id) do
    case String.trim(effect_id) do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize_effect_id(_effect_id, conversation_id, attempt)
       when is_binary(conversation_id) do
    normalized_conversation_id =
      case String.trim(conversation_id) do
        "" -> "unknown"
        value -> value
      end

    normalized_attempt =
      case attempt do
        value when is_integer(value) and value >= 0 -> Integer.to_string(value)
        value when is_binary(value) -> value
        _ -> "0"
      end

    "#{normalized_conversation_id}:#{normalized_attempt}:unknown_effect"
  end

  defp normalize_effect_id(_effect_id, _conversation_id, _attempt), do: nil

  defp truthy?(true), do: true
  defp truthy?("true"), do: true
  defp truthy?(1), do: true
  defp truthy?(_value), do: false

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
      last_dispatch_failure: state.last_dispatch_failure,
      llm: %{
        lifecycle_counts: state.llm_lifecycle_counts,
        lifecycle_by_backend: state.llm_lifecycle_by_backend,
        cancel_latency_ms: latency_summary(state.llm_cancel_latency_us),
        stream_duration_ms: latency_summary(state.llm_stream_duration_us),
        stream_chunks: state.llm_stream_chunks,
        retry_by_category: state.llm_retry_by_category,
        cancel_results: state.llm_cancel_results
      }
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
