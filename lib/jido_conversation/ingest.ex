defmodule JidoConversation.Ingest do
  @moduledoc """
  Public API for journal-first event ingestion and queries.
  """

  alias JidoConversation.ConversationRef
  alias JidoConversation.Ingest.Pipeline

  @spec ingest(JidoConversation.Signal.Contract.input(), keyword()) ::
          {:ok, JidoConversation.Ingest.Pipeline.ingest_result()}
          | {:error, JidoConversation.Ingest.Pipeline.ingest_error()}
  def ingest(attrs, opts \\ []) do
    Pipeline.ingest(attrs, opts)
  end

  @spec conversation_events(String.t()) :: [Jido.Signal.t()]
  def conversation_events(conversation_id) do
    Pipeline.conversation_events(conversation_id)
  end

  @spec conversation_events(String.t(), String.t()) :: [Jido.Signal.t()]
  def conversation_events(project_id, conversation_id)
      when is_binary(project_id) and is_binary(conversation_id) do
    project_id
    |> ConversationRef.subject(conversation_id)
    |> conversation_events()
  end

  @spec trace_chain(String.t(), :forward | :backward) :: [Jido.Signal.t()]
  def trace_chain(signal_id, direction \\ :forward) do
    Pipeline.trace_chain(signal_id, direction)
  end

  @spec replay(String.t(), non_neg_integer(), keyword()) ::
          {:ok, [Jido.Signal.Bus.RecordedSignal.t()]} | {:error, term()}
  def replay(path \\ "conv.**", start_timestamp \\ 0, opts \\ []) do
    Pipeline.replay(path, start_timestamp, opts)
  end
end
