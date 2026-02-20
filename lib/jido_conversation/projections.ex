defmodule JidoConversation.Projections do
  @moduledoc """
  Projection facade for timeline and LLM context views.
  """

  alias JidoConversation.Ingest
  alias JidoConversation.Projections.LlmContext
  alias JidoConversation.Projections.Timeline

  @spec timeline(String.t(), keyword()) :: [Timeline.timeline_entry()]
  def timeline(conversation_id, opts \\ []) when is_binary(conversation_id) and is_list(opts) do
    conversation_id
    |> Ingest.conversation_events()
    |> Timeline.from_events(opts)
  end

  @spec llm_context(String.t(), keyword()) :: [LlmContext.context_message()]
  def llm_context(conversation_id, opts \\ [])
      when is_binary(conversation_id) and is_list(opts) do
    conversation_id
    |> Ingest.conversation_events()
    |> LlmContext.from_events(opts)
  end
end
