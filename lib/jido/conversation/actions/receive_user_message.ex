defmodule Jido.Conversation.Actions.ReceiveUserMessage do
  @moduledoc """
  Registers a user message in conversation state.
  """

  {:nowarn_function,
   [
     run: 2,
     on_error: 4,
     on_before_validate_params: 1,
     on_after_validate_params: 1,
     on_before_validate_output: 1,
     on_after_validate_output: 1
   ]}

  use Jido.Action,
    name: "conversation_receive_user_message",
    description: "Registers a user message",
    schema: [
      content: [type: :string, required: true],
      metadata: [type: :map, default: %{}]
    ]

  @impl true
  def run(%{content: content, metadata: metadata}, context) do
    state = Map.get(context, :state, %{})

    messages = Map.get(state, :messages, [])
    turn = Map.get(state, :turn, 0) + 1

    message = %{
      id: "user-" <> Jido.Util.generate_id(),
      role: "user",
      content: content,
      turn: turn,
      at: System.system_time(:millisecond),
      metadata: metadata
    }

    {:ok,
     %{
       status: :pending_llm,
       turn: turn,
       cancel_requested?: false,
       last_user_message: content,
       messages: messages ++ [message]
     }}
  end
end
