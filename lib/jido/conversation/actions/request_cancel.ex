defmodule Jido.Conversation.Actions.RequestCancel do
  @moduledoc """
  Marks a conversation as canceled.
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
    name: "conversation_request_cancel",
    description: "Marks a conversation as canceled",
    schema: [
      reason: [type: :string, default: "cancel_requested"]
    ]

  @impl true
  def run(%{reason: reason}, _context) do
    {:ok,
     %{
       status: :canceled,
       cancel_requested?: true,
       cancel_reason: reason,
       canceled_at: System.system_time(:millisecond)
     }}
  end
end
