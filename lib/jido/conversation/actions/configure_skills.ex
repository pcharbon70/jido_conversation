defmodule Jido.Conversation.Actions.ConfigureSkills do
  @moduledoc """
  Configures the enabled skill set for a conversation.
  """

  @dialyzer {:no_contracts,
             [
               run: 2,
               on_error: 4,
               on_before_validate_params: 1,
               on_after_validate_params: 1,
               on_before_validate_output: 1,
               on_after_validate_output: 1
             ]}

  use Jido.Action,
    name: "conversation_configure_skills",
    description: "Sets enabled skill identifiers for this conversation",
    schema: [
      enabled: [type: {:list, :string}, default: []]
    ]

  @impl true
  def run(%{enabled: enabled}, _context) when is_list(enabled) do
    {:ok, %{skills: %{enabled: normalize_enabled(enabled)}}}
  end

  defp normalize_enabled(enabled) do
    enabled
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end
end
