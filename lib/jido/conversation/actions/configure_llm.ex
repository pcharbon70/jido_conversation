defmodule Jido.Conversation.Actions.ConfigureLlm do
  @moduledoc """
  Configures the selected LLM backend/model policy for a conversation.
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
    name: "conversation_configure_llm",
    description: "Sets LLM backend/provider/model for this conversation",
    schema: [
      backend: [type: :atom, required: true],
      provider: [type: :string],
      model: [type: :string],
      options: [type: :map, default: %{}]
    ]

  @impl true
  def run(%{backend: backend} = params, _context) do
    llm = %{
      backend: backend,
      provider: Map.get(params, :provider),
      model: Map.get(params, :model),
      options: Map.get(params, :options, %{})
    }

    {:ok, %{llm: llm}}
  end
end
