defmodule Jido.Conversation do
  @moduledoc """
  Entry points for the conversation runtime.
  """

  alias Jido.Conversation.Health
  alias Jido.Conversation.Ingest
  alias Jido.Conversation.Projections
  alias Jido.Conversation.Telemetry, as: RuntimeTelemetry

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
  @spec ingest(Jido.Conversation.Signal.Contract.input(), keyword()) ::
          {:ok, Jido.Conversation.Ingest.Pipeline.ingest_result()}
          | {:error, Jido.Conversation.Ingest.Pipeline.ingest_error()}
  def ingest(attrs, opts \\ []) do
    Ingest.ingest(attrs, opts)
  end

  @doc """
  Builds a user-facing timeline projection for a conversation.
  """
  @spec timeline(String.t(), keyword()) :: [
          Jido.Conversation.Projections.Timeline.timeline_entry()
        ]
  def timeline(conversation_id, opts \\ []) do
    Projections.timeline(conversation_id, opts)
  end

  @doc """
  Builds an LLM context projection for a conversation.
  """
  @spec llm_context(String.t(), keyword()) :: [
          Jido.Conversation.Projections.LlmContext.context_message()
        ]
  def llm_context(conversation_id, opts \\ []) do
    Projections.llm_context(conversation_id, opts)
  end

  @doc """
  Returns aggregated runtime telemetry metrics.
  """
  @spec telemetry_snapshot() :: Jido.Conversation.Telemetry.metrics_snapshot()
  def telemetry_snapshot do
    RuntimeTelemetry.snapshot()
  end
end
