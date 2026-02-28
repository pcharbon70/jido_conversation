defmodule Jido.Conversation.Projections.Timeline do
  @moduledoc """
  Builds a human-readable timeline from thread entries.
  """

  alias Jido.Thread.Entry

  @type entry :: %{
          entry_id: String.t(),
          seq: non_neg_integer(),
          role: :user | :assistant | :system | :tool,
          kind: :message | :status,
          content: String.t(),
          metadata: map()
        }

  @spec from_entries([Entry.t()]) :: [entry()]
  def from_entries(entries) when is_list(entries) do
    entries
    |> Enum.sort_by(& &1.seq)
    |> Enum.map(&to_timeline_entry/1)
    |> Enum.reject(&is_nil/1)
  end

  defp to_timeline_entry(%Entry{kind: :message} = entry) do
    role = normalize_role(get_field(entry.payload, :role))
    content = to_string(get_field(entry.payload, :content) || "")
    metadata = normalize_map(get_field(entry.payload, :metadata))

    %{
      entry_id: entry.id,
      seq: entry.seq,
      role: role,
      kind: :message,
      content: content,
      metadata: metadata
    }
  end

  defp to_timeline_entry(%Entry{kind: :note} = entry) do
    case get_field(entry.payload, :event) do
      "cancel_requested" ->
        reason = get_field(entry.payload, :reason) || "cancel_requested"

        %{
          entry_id: entry.id,
          seq: entry.seq,
          role: :system,
          kind: :status,
          content: "Cancel requested (#{reason})",
          metadata: %{event: "cancel_requested"}
        }

      "llm_configured" ->
        backend = get_field(entry.payload, :backend)
        provider = get_field(entry.payload, :provider)
        model = get_field(entry.payload, :model)

        %{
          entry_id: entry.id,
          seq: entry.seq,
          role: :system,
          kind: :status,
          content: "LLM configured",
          metadata: %{event: "llm_configured", backend: backend, provider: provider, model: model}
        }

      "skills_configured" ->
        enabled = get_field(entry.payload, :enabled) || []

        %{
          entry_id: entry.id,
          seq: entry.seq,
          role: :system,
          kind: :status,
          content: "Skills configured",
          metadata: %{event: "skills_configured", enabled: enabled}
        }

      _other ->
        nil
    end
  end

  defp to_timeline_entry(_entry), do: nil

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

  defp normalize_map(value) when is_map(value), do: value
  defp normalize_map(_), do: %{}
end
