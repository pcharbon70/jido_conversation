defmodule Jido.Conversation.Ingest do
  @moduledoc """
  Public API for journal-first event ingestion and queries.
  """

  alias Jido.Conversation.Ingest.Pipeline

  @spec ingest(Jido.Conversation.Signal.Contract.input(), keyword()) ::
          {:ok, Jido.Conversation.Ingest.Pipeline.ingest_result()}
          | {:error, Jido.Conversation.Ingest.Pipeline.ingest_error()}
  def ingest(attrs, opts \\ []) do
    Pipeline.ingest(attrs, opts)
  end

  @spec conversation_events(String.t()) :: [Jido.Signal.t()]
  def conversation_events(conversation_id) do
    Pipeline.conversation_events(conversation_id)
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
