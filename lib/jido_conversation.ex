defmodule JidoConversation do
  @moduledoc """
  Entry points for the conversation runtime.
  """

  alias JidoConversation.Health
  alias JidoConversation.Ingest
  alias JidoConversation.Projections

  @doc """
  Returns runtime health details for the signal bus and runtime supervisors.
  """
  @spec health() :: Health.status_map()
  def health do
    Health.status()
  end

  @doc """
  Ingests an event through the journal-first pipeline.
  """
  @spec ingest(JidoConversation.Signal.Contract.input(), keyword()) ::
          {:ok, JidoConversation.Ingest.Pipeline.ingest_result()}
          | {:error, JidoConversation.Ingest.Pipeline.ingest_error()}
  def ingest(attrs, opts \\ []) do
    Ingest.ingest(attrs, opts)
  end

  @doc """
  Builds a user-facing timeline projection for a conversation.
  """
  @spec timeline(String.t(), keyword()) :: [
          JidoConversation.Projections.Timeline.timeline_entry()
        ]
  def timeline(conversation_id, opts \\ []) do
    Projections.timeline(conversation_id, opts)
  end

  @doc """
  Builds an LLM context projection for a conversation.
  """
  @spec llm_context(String.t(), keyword()) :: [
          JidoConversation.Projections.LlmContext.context_message()
        ]
  def llm_context(conversation_id, opts \\ []) do
    Projections.llm_context(conversation_id, opts)
  end
end
