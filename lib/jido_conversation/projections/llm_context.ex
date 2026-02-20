defmodule JidoConversation.Projections.LlmContext do
  @moduledoc """
  Derives a role/content LLM context projection from timeline entries.
  """

  alias Jido.Signal
  alias JidoConversation.Projections.Timeline

  @type context_message :: %{
          role: :user | :assistant | :tool | :system,
          content: String.t(),
          event_id: String.t()
        }

  @spec from_events([Signal.t()], keyword()) :: [context_message()]
  def from_events(events, opts \\ []) when is_list(events) and is_list(opts) do
    include_deltas? = Keyword.get(opts, :include_deltas, false)
    include_tool_status? = Keyword.get(opts, :include_tool_status, true)
    max_messages = Keyword.get(opts, :max_messages, 40)

    events
    |> Timeline.from_events(coalesce_deltas: true)
    |> Enum.reduce([], fn entry, acc ->
      case entry_to_context(entry, include_deltas?, include_tool_status?) do
        nil -> acc
        context_entry -> [context_entry | acc]
      end
    end)
    |> Enum.reverse()
    |> tail(max_messages)
  end

  defp entry_to_context(%{role: :user, kind: :message} = entry, _include_deltas?, _include_tool?) do
    %{
      role: :user,
      content: to_string(entry.content || ""),
      event_id: entry.event_id
    }
  end

  defp entry_to_context(
         %{role: :assistant, kind: :message} = entry,
         _include_deltas?,
         _include_tool?
       ) do
    %{
      role: :assistant,
      content: to_string(entry.content || ""),
      event_id: entry.event_id
    }
  end

  defp entry_to_context(
         %{role: :assistant, kind: :delta} = entry,
         true,
         _include_tool?
       ) do
    %{
      role: :assistant,
      content: to_string(entry.content || ""),
      event_id: entry.event_id
    }
  end

  defp entry_to_context(%{role: :tool, kind: :status} = entry, _include_deltas?, true) do
    %{
      role: :tool,
      content: to_string(entry.content || ""),
      event_id: entry.event_id
    }
  end

  defp entry_to_context(_entry, _include_deltas?, _include_tool?), do: nil

  defp tail(entries, max_messages) when is_integer(max_messages) and max_messages > 0 do
    Enum.take(entries, -max_messages)
  end

  defp tail(entries, _max_messages), do: entries
end
