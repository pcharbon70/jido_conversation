defmodule Jido.Conversation.Projections.LlmContext do
  @moduledoc """
  Derives LLM context messages from thread entries.
  """

  alias Jido.Thread.Entry

  @type message :: %{
          role: :user | :assistant | :system | :tool,
          content: String.t(),
          entry_id: String.t()
        }

  @spec from_entries([Entry.t()], keyword()) :: [message()]
  def from_entries(entries, opts \\ []) when is_list(entries) and is_list(opts) do
    max_messages = Keyword.get(opts, :max_messages, 40)
    include_system? = Keyword.get(opts, :include_system, false)
    include_tool? = Keyword.get(opts, :include_tool, false)

    entries
    |> Enum.sort_by(& &1.seq)
    |> Enum.reduce([], fn entry, acc ->
      case to_context_message(entry, include_system?, include_tool?) do
        nil -> acc
        message -> [message | acc]
      end
    end)
    |> Enum.reverse()
    |> tail(max_messages)
  end

  defp to_context_message(%Entry{kind: :message} = entry, include_system?, include_tool?) do
    role = normalize_role(get_field(entry.payload, :role))
    content = to_string(get_field(entry.payload, :content) || "")

    cond do
      role == :system and not include_system? ->
        nil

      role == :tool and not include_tool? ->
        nil

      String.trim(content) == "" ->
        nil

      true ->
        %{role: role, content: content, entry_id: entry.id}
    end
  end

  defp to_context_message(_entry, _include_system?, _include_tool?), do: nil

  defp tail(entries, max_messages) when is_integer(max_messages) and max_messages > 0 do
    Enum.take(entries, -max_messages)
  end

  defp tail(entries, _max_messages), do: entries

  defp normalize_role("user"), do: :user
  defp normalize_role("assistant"), do: :assistant
  defp normalize_role("system"), do: :system
  defp normalize_role("tool"), do: :tool
  defp normalize_role(role) when role in [:user, :assistant, :system, :tool], do: role
  defp normalize_role(_), do: :user

  defp get_field(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, to_string(key))
  end

  defp get_field(_map, _key), do: nil
end
