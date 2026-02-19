defmodule JidoConversation.Runtime.Reducer do
  @moduledoc """
  Pure conversation reducer.

  Accepts one signal at a time and returns updated conversation state plus
  directives that the runtime executes as side effects.
  """

  alias Jido.Signal

  @max_history 100

  @type conversation_state :: %{
          conversation_id: String.t(),
          applied_count: non_neg_integer(),
          stream_counts: map(),
          flags: map(),
          in_flight_effects: map(),
          last_event: map() | nil,
          history: [map()]
        }

  @type directive ::
          %{
            type: :emit_applied_marker,
            payload: %{
              applied_event_id: String.t(),
              original_type: String.t(),
              subject: String.t(),
              priority: non_neg_integer(),
              partition_id: non_neg_integer(),
              scheduler_seq: non_neg_integer()
            },
            cause_id: String.t()
          }

  @spec new(String.t()) :: conversation_state()
  def new(conversation_id) when is_binary(conversation_id) do
    %{
      conversation_id: conversation_id,
      applied_count: 0,
      stream_counts: %{},
      flags: %{},
      in_flight_effects: %{},
      last_event: nil,
      history: []
    }
  end

  @spec apply_event(conversation_state(), Signal.t(), keyword()) ::
          {:ok, conversation_state(), [directive()]}
  def apply_event(state, %Signal{} = signal, opts \\ []) do
    priority = Keyword.fetch!(opts, :priority)
    partition_id = Keyword.fetch!(opts, :partition_id)
    scheduler_seq = Keyword.fetch!(opts, :scheduler_seq)

    state =
      state
      |> increment_applied_count()
      |> increment_stream_count(signal.type)
      |> update_flags(signal)
      |> update_in_flight_effects(signal)
      |> update_last_event(signal, priority, scheduler_seq)
      |> append_history(signal, priority, scheduler_seq)

    directives =
      if String.starts_with?(signal.type, "conv.applied.") do
        []
      else
        [
          %{
            type: :emit_applied_marker,
            payload: %{
              applied_event_id: signal.id,
              original_type: signal.type,
              subject: signal.subject || "default",
              priority: priority,
              partition_id: partition_id,
              scheduler_seq: scheduler_seq
            },
            cause_id: signal.id
          }
        ]
      end

    {:ok, state, directives}
  end

  defp increment_applied_count(state) do
    %{state | applied_count: state.applied_count + 1}
  end

  defp increment_stream_count(state, type) do
    stream = stream_family(type)

    %{state | stream_counts: Map.update(state.stream_counts, stream, 1, &(&1 + 1))}
  end

  defp update_flags(state, %Signal{type: "conv.in.control.abort_requested"}) do
    %{state | flags: Map.put(state.flags, :abort_requested, true)}
  end

  defp update_flags(state, _signal), do: state

  defp update_in_flight_effects(state, %Signal{} = signal) do
    if String.starts_with?(signal.type, "conv.effect.") do
      effect_id = get_field(signal.data, :effect_id)
      lifecycle = get_field(signal.data, :lifecycle)

      case {effect_id, lifecycle} do
        {id, "started"} when is_binary(id) ->
          %{state | in_flight_effects: Map.put(state.in_flight_effects, id, :started)}

        {id, status} when is_binary(id) and status in ["progress"] ->
          %{state | in_flight_effects: Map.put(state.in_flight_effects, id, :progress)}

        {id, status} when is_binary(id) and status in ["completed", "failed", "canceled"] ->
          %{state | in_flight_effects: Map.delete(state.in_flight_effects, id)}

        _ ->
          state
      end
    else
      state
    end
  end

  defp update_last_event(state, %Signal{} = signal, priority, scheduler_seq) do
    %{
      state
      | last_event: %{id: signal.id, type: signal.type, priority: priority, seq: scheduler_seq}
    }
  end

  defp append_history(state, %Signal{} = signal, priority, scheduler_seq) do
    new_entry = %{id: signal.id, type: signal.type, priority: priority, seq: scheduler_seq}

    history =
      [new_entry | state.history]
      |> Enum.take(@max_history)

    %{state | history: history}
  end

  defp stream_family(type) when is_binary(type) do
    cond do
      String.starts_with?(type, "conv.in.") -> :in
      String.starts_with?(type, "conv.applied.") -> :applied
      String.starts_with?(type, "conv.effect.") -> :effect
      String.starts_with?(type, "conv.out.") -> :out
      String.starts_with?(type, "conv.audit.") -> :audit
      true -> :unknown
    end
  end

  defp get_field(data, key) when is_map(data) do
    Map.get(data, key) || Map.get(data, to_string(key))
  end

  defp get_field(_data, _key), do: nil
end
