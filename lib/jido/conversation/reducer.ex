defmodule Jido.Conversation.Reducer do
  @moduledoc """
  Pure state derivation from append-only thread entries.
  """

  alias Jido.Thread.Entry

  @type derived_state :: %{
          status: :idle | :pending_llm | :responding | :canceled | :error,
          turn: non_neg_integer(),
          cancel_requested?: boolean(),
          cancel_reason: String.t() | nil,
          last_user_message: String.t() | nil,
          messages: [map()],
          llm: map(),
          skills: %{enabled: [String.t()]}
        }

  @default_llm %{backend: :jido_ai, provider: nil, model: nil, options: %{}}

  @spec derive([Entry.t()], keyword()) :: derived_state()
  def derive(entries, opts \\ []) when is_list(entries) and is_list(opts) do
    default_llm =
      @default_llm
      |> deep_merge(opts |> Keyword.get(:default_llm, %{}) |> normalize_map())

    entries
    |> Enum.sort_by(& &1.seq)
    |> Enum.reduce(initial_state(default_llm), &apply_entry/2)
  end

  defp initial_state(default_llm) do
    %{
      status: :idle,
      turn: 0,
      cancel_requested?: false,
      cancel_reason: nil,
      last_user_message: nil,
      messages: [],
      llm: default_llm,
      skills: %{enabled: []}
    }
  end

  defp apply_entry(%Entry{kind: :message} = entry, state) do
    role = normalize_role(get_field(entry.payload, :role))
    content = to_string(get_field(entry.payload, :content) || "")
    metadata = normalize_map(get_field(entry.payload, :metadata))

    message = %{
      entry_id: entry.id,
      seq: entry.seq,
      role: role,
      content: content,
      metadata: metadata
    }

    state
    |> Map.put(:messages, state.messages ++ [message])
    |> maybe_increment_turn(role)
    |> maybe_set_last_user_message(role, content)
    |> maybe_set_status_from_role(role)
  end

  defp apply_entry(%Entry{kind: :note} = entry, state) do
    event = get_field(entry.payload, :event)

    case event do
      "cancel_requested" ->
        reason = get_field(entry.payload, :reason) || "cancel_requested"

        %{state | status: :canceled, cancel_requested?: true, cancel_reason: to_string(reason)}

      "llm_configured" ->
        llm = %{
          backend: normalize_backend(get_field(entry.payload, :backend)),
          provider: get_field(entry.payload, :provider),
          model: get_field(entry.payload, :model),
          options: normalize_map(get_field(entry.payload, :options))
        }

        %{state | llm: deep_merge(state.llm, compact_map(llm))}

      "skills_configured" ->
        enabled = normalize_skill_list(get_field(entry.payload, :enabled))
        %{state | skills: %{enabled: enabled}}

      _other ->
        state
    end
  end

  defp apply_entry(_entry, state), do: state

  defp maybe_increment_turn(state, :user), do: %{state | turn: state.turn + 1}
  defp maybe_increment_turn(state, _role), do: state

  defp maybe_set_last_user_message(state, :user, content),
    do: %{state | last_user_message: content}

  defp maybe_set_last_user_message(state, _role, _content), do: state

  defp maybe_set_status_from_role(state, :user), do: %{state | status: :pending_llm}
  defp maybe_set_status_from_role(state, :assistant), do: %{state | status: :responding}
  defp maybe_set_status_from_role(state, _role), do: state

  defp normalize_role("user"), do: :user
  defp normalize_role("assistant"), do: :assistant
  defp normalize_role("system"), do: :system
  defp normalize_role("tool"), do: :tool
  defp normalize_role(role) when role in [:user, :assistant, :system, :tool], do: role
  defp normalize_role(_), do: :user

  defp normalize_backend(value) when is_atom(value), do: value
  defp normalize_backend("jido_ai"), do: :jido_ai
  defp normalize_backend("harness"), do: :harness
  defp normalize_backend(_), do: nil

  defp get_field(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, to_string(key))
  end

  defp get_field(_map, _key), do: nil

  defp normalize_skill_list(value) when is_list(value) do
    value
    |> Enum.map(fn
      skill when is_atom(skill) -> Atom.to_string(skill)
      skill when is_binary(skill) -> String.trim(skill)
      _other -> ""
    end)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp normalize_skill_list(_value), do: []

  defp normalize_map(value) when is_map(value), do: value
  defp normalize_map(_), do: %{}

  defp compact_map(map) when is_map(map) do
    Enum.reduce(map, %{}, fn
      {_key, nil}, acc -> acc
      {key, value}, acc -> Map.put(acc, key, value)
    end)
  end

  defp deep_merge(left, right) when is_map(left) and is_map(right) do
    Map.merge(left, right, fn _key, l, r ->
      if is_map(l) and is_map(r), do: deep_merge(l, r), else: r
    end)
  end
end
