defmodule Jido.Conversation.Projections.TokenCoalescer do
  @moduledoc """
  Coalesces adjacent assistant delta entries to reduce high-volume output noise.
  """

  @default_max_chars 280

  @spec coalesce([map()], keyword()) :: [map()]
  def coalesce(entries, opts \\ []) when is_list(entries) and is_list(opts) do
    max_chars = Keyword.get(opts, :max_chars, @default_max_chars)

    entries
    |> Enum.reduce([], fn entry, acc -> coalesce_entry(acc, entry, max_chars) end)
    |> Enum.reverse()
  end

  defp coalesce_entry([prev | rest], entry, max_chars) do
    if mergeable?(prev, entry, max_chars) do
      [merge_entries(prev, entry) | rest]
    else
      [entry, prev | rest]
    end
  end

  defp coalesce_entry([], entry, _max_chars), do: [entry]

  defp mergeable?(left, right, max_chars) do
    left[:role] == :assistant and left[:kind] == :delta and right[:role] == :assistant and
      right[:kind] == :delta and left[:output_id] == right[:output_id] and
      left[:channel] == right[:channel] and
      String.length(to_string(left[:content] || "")) +
        String.length(to_string(right[:content] || "")) <=
        max_chars
  end

  defp merge_entries(left, right) do
    content = to_string(left[:content] || "") <> to_string(right[:content] || "")

    merged_ids =
      (List.wrap(left[:event_ids]) ++
         [left[:event_id]] ++
         List.wrap(right[:event_ids]) ++
         [right[:event_id]])
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    left
    |> Map.put(:content, content)
    |> Map.put(:event_ids, merged_ids)
  end
end
