defmodule JidoConversation.Runtime.Reducer do
  @moduledoc """
  Pure conversation reducer.

  Accepts one signal at a time and returns updated conversation state plus
  directives that the runtime executes as side effects.
  """

  alias Jido.Signal

  @max_history 100
  @effect_id_prefixes %{
    llm: "llm-generation",
    tool: "tool-execution",
    timer: "timer-wait"
  }

  @type conversation_state :: %{
          conversation_id: String.t(),
          applied_count: non_neg_integer(),
          stream_counts: map(),
          flags: map(),
          in_flight_effects: map(),
          last_event: map() | nil,
          history: [map()]
        }

  @type applied_marker_directive :: %{
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

  @type start_effect_directive :: %{
          type: :start_effect,
          payload: %{
            effect_id: String.t(),
            conversation_id: String.t(),
            class: :llm | :tool | :timer,
            kind: String.t(),
            input: map(),
            simulate: map(),
            policy: keyword() | map()
          },
          cause_id: String.t()
        }

  @type cancel_effects_directive :: %{
          type: :cancel_effects,
          payload: %{
            conversation_id: String.t(),
            reason: String.t()
          },
          cause_id: String.t()
        }

  @type emit_output_directive :: %{
          type: :emit_output,
          payload: %{
            conversation_id: String.t(),
            output_type: String.t(),
            output_id: String.t(),
            channel: String.t(),
            source: String.t(),
            data: map()
          },
          cause_id: String.t()
        }

  @type directive ::
          applied_marker_directive()
          | start_effect_directive()
          | cancel_effects_directive()
          | emit_output_directive()

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
        derived_directives = effect_directives(state, signal) ++ output_directives(signal)

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
          | derived_directives
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

  defp update_flags(state, %Signal{type: "conv.in.control.stop_requested"}) do
    %{state | flags: Map.put(state.flags, :stop_requested, true)}
  end

  defp update_flags(state, %Signal{type: "conv.in.control.cancel_requested"}) do
    %{state | flags: Map.put(state.flags, :cancel_requested, true)}
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

  defp effect_directives(_state, %Signal{type: "conv.in.message.received"} = signal) do
    [start_effect_directive(signal, :llm, "generation")]
  end

  defp effect_directives(_state, %Signal{type: "conv.in.timer.tick"} = signal) do
    [start_effect_directive(signal, :timer, "wait")]
  end

  defp effect_directives(state, %Signal{type: "conv.in.control.abort_requested"} = signal) do
    [
      %{
        type: :cancel_effects,
        payload: %{
          conversation_id: state.conversation_id,
          reason: signal.type
        },
        cause_id: signal.id
      }
    ]
  end

  defp effect_directives(state, %Signal{type: "conv.in.control.stop_requested"} = signal) do
    [
      %{
        type: :cancel_effects,
        payload: %{
          conversation_id: state.conversation_id,
          reason: signal.type
        },
        cause_id: signal.id
      }
    ]
  end

  defp effect_directives(_state, _signal), do: []

  defp output_directives(%Signal{type: "conv.effect.llm.generation.progress"} = signal) do
    case assistant_delta_directive(signal) do
      nil -> []
      directive -> [directive]
    end
  end

  defp output_directives(%Signal{type: "conv.effect.llm.generation.completed"} = signal) do
    [assistant_completed_directive(signal)]
  end

  defp output_directives(
         %Signal{type: <<"conv.effect.tool.execution.", lifecycle::binary>>} = signal
       )
       when lifecycle in ["started", "progress", "completed", "failed", "canceled"] do
    [tool_status_directive(signal, lifecycle)]
  end

  defp output_directives(_signal), do: []

  defp start_effect_directive(%Signal{} = signal, class, kind) do
    payload = %{
      effect_id: "#{effect_id_prefix(class)}-#{signal.id}",
      conversation_id: signal.subject || "default",
      class: class,
      kind: kind,
      input: normalize_map(signal.data),
      simulate: normalize_map(get_field(signal.data, :simulate_effect)),
      policy: get_field(signal.data, :effect_policy) || []
    }

    %{
      type: :start_effect,
      payload: payload,
      cause_id: signal.id
    }
  end

  defp assistant_delta_directive(%Signal{} = signal) do
    delta =
      first_non_empty([
        get_field(signal.data, :token_delta),
        get_field(signal.data, :delta),
        get_nested_field(signal.data, :result, :delta),
        get_nested_field(signal.data, :result, :text),
        get_field(signal.data, :status)
      ])

    if is_binary(delta) and String.trim(delta) != "" do
      effect_id = get_field(signal.data, :effect_id) || signal.id
      output_id = "assistant-#{effect_id}"

      output_directive(
        signal,
        "conv.out.assistant.delta",
        output_id,
        output_channel(signal),
        %{
          effect_id: effect_id,
          lifecycle: "progress",
          delta: delta
        }
      )
    end
  end

  defp assistant_completed_directive(%Signal{} = signal) do
    effect_id = get_field(signal.data, :effect_id) || signal.id
    output_id = "assistant-#{effect_id}"

    content =
      first_non_empty([
        get_field(signal.data, :content),
        get_nested_field(signal.data, :result, :text),
        get_nested_field(signal.data, :result, :summary),
        format_result(get_field(signal.data, :result))
      ]) || "completed"

    output_directive(
      signal,
      "conv.out.assistant.completed",
      output_id,
      output_channel(signal),
      %{
        effect_id: effect_id,
        lifecycle: "completed",
        content: content
      }
    )
  end

  defp tool_status_directive(%Signal{} = signal, lifecycle) do
    effect_id = get_field(signal.data, :effect_id) || signal.id
    output_id = "tool-#{effect_id}"

    message =
      first_non_empty([
        get_field(signal.data, :message),
        get_field(signal.data, :reason),
        get_field(signal.data, :status),
        lifecycle
      ])

    output_directive(
      signal,
      "conv.out.tool.status",
      output_id,
      output_channel(signal),
      %{
        effect_id: effect_id,
        lifecycle: lifecycle,
        message: message
      }
    )
  end

  defp output_directive(%Signal{} = signal, output_type, output_id, channel, data) do
    %{
      type: :emit_output,
      payload: %{
        conversation_id: signal.subject || "default",
        output_type: output_type,
        output_id: output_id,
        channel: channel,
        source: "/runtime/projections",
        data: data
      },
      cause_id: signal.id
    }
  end

  defp output_channel(%Signal{} = signal) do
    first_non_empty([
      get_field(signal.data, :channel),
      get_field(signal.data, :ingress),
      "primary"
    ])
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

  defp get_nested_field(data, parent_key, child_key) when is_map(data) do
    case get_field(data, parent_key) do
      nested when is_map(nested) -> get_field(nested, child_key)
      _ -> nil
    end
  end

  defp get_nested_field(_data, _parent_key, _child_key), do: nil

  defp first_non_empty(values) when is_list(values) do
    Enum.find(values, fn
      value when is_binary(value) -> String.trim(value) != ""
      nil -> false
      _ -> true
    end)
  end

  defp format_result(nil), do: nil
  defp format_result(result) when is_binary(result), do: result
  defp format_result(result) when is_map(result), do: inspect(result)
  defp format_result(_result), do: nil

  defp normalize_map(value) when is_map(value), do: value
  defp normalize_map(_value), do: %{}

  defp effect_id_prefix(class) when class in [:llm, :tool, :timer] do
    Map.fetch!(@effect_id_prefixes, class)
  end
end
