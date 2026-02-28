defmodule Jido.Conversation.Actions.RecordAssistantMessage do
  @moduledoc """
  Registers an assistant message in conversation state.
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
    name: "conversation_record_assistant_message",
    description: "Registers an assistant message",
    schema: [
      content: [type: :string, required: true],
      metadata: [type: :map, default: %{}]
    ]

  @impl true
  def run(%{content: content, metadata: metadata}, context) do
    state = Map.get(context, :state, %{})
    messages = Map.get(state, :messages, [])

    message = %{
      id: "assistant-" <> Jido.Util.generate_id(),
      role: "assistant",
      content: content,
      turn: Map.get(state, :turn, 0),
      at: System.system_time(:millisecond),
      metadata: metadata
    }

    {:ok,
     %{
       status: :responding,
       messages: messages ++ [message]
     }}
  end
end
