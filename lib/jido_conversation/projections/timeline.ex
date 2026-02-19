defmodule JidoConversation.Projections.Timeline do
  @moduledoc """
  Builds a user-facing timeline projection from conversation events.
  """

  alias Jido.Signal
  alias JidoConversation.Projections.TokenCoalescer

  @type timeline_entry :: %{
          event_id: String.t(),
          type: String.t(),
          role: :user | :assistant | :tool,
          kind: :message | :delta | :status,
          output_id: String.t() | nil,
          channel: String.t() | nil,
          content: String.t(),
          metadata: map()
        }

  @spec from_events([Signal.t()], keyword()) :: [timeline_entry()]
  def from_events(events, opts \\ []) when is_list(events) and is_list(opts) do
    coalesce_deltas? = Keyword.get(opts, :coalesce_deltas, true)
    max_chars = Keyword.get(opts, :max_delta_chars, 280)

    entries =
      events
      |> Enum.sort_by(& &1.id)
      |> Enum.map(&entry_for_signal/1)
      |> Enum.reject(&is_nil/1)

    if coalesce_deltas? do
      TokenCoalescer.coalesce(entries, max_chars: max_chars)
    else
      entries
    end
  end

  defp entry_for_signal(%Signal{type: "conv.in.message.received"} = signal) do
    content =
      first_non_empty([
        get_field(signal.data, :content),
        get_field(signal.data, :text),
        get_field(signal.data, :body),
        get_field(signal.data, :message)
      ]) || ""

    %{
      event_id: signal.id,
      type: signal.type,
      role: :user,
      kind: :message,
      output_id: nil,
      channel: get_field(signal.data, :ingress),
      content: content,
      metadata: %{
        message_id: get_field(signal.data, :message_id)
      }
    }
  end

  defp entry_for_signal(%Signal{type: "conv.out.assistant.delta"} = signal) do
    %{
      event_id: signal.id,
      type: signal.type,
      role: :assistant,
      kind: :delta,
      output_id: get_field(signal.data, :output_id),
      channel: get_field(signal.data, :channel),
      content: to_string(get_field(signal.data, :delta) || ""),
      metadata: %{
        effect_id: get_field(signal.data, :effect_id),
        lifecycle: get_field(signal.data, :lifecycle)
      }
    }
  end

  defp entry_for_signal(%Signal{type: "conv.out.assistant.completed"} = signal) do
    %{
      event_id: signal.id,
      type: signal.type,
      role: :assistant,
      kind: :message,
      output_id: get_field(signal.data, :output_id),
      channel: get_field(signal.data, :channel),
      content: to_string(get_field(signal.data, :content) || ""),
      metadata: %{
        effect_id: get_field(signal.data, :effect_id),
        lifecycle: get_field(signal.data, :lifecycle)
      }
    }
  end

  defp entry_for_signal(%Signal{type: "conv.out.tool.status"} = signal) do
    %{
      event_id: signal.id,
      type: signal.type,
      role: :tool,
      kind: :status,
      output_id: get_field(signal.data, :output_id),
      channel: get_field(signal.data, :channel),
      content:
        to_string(get_field(signal.data, :message) || get_field(signal.data, :status) || ""),
      metadata: %{
        effect_id: get_field(signal.data, :effect_id),
        lifecycle: get_field(signal.data, :lifecycle)
      }
    }
  end

  defp entry_for_signal(_signal), do: nil

  defp get_field(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, to_string(key))
  end

  defp get_field(_map, _key), do: nil

  defp first_non_empty(values) when is_list(values) do
    Enum.find(values, fn
      value when is_binary(value) -> String.trim(value) != ""
      nil -> false
      _ -> true
    end)
  end
end
