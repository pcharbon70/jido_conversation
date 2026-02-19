defmodule JidoConversation do
  @moduledoc """
  Entry points for the conversation runtime.
  """

  alias JidoConversation.Health
  alias JidoConversation.Ingest
  alias JidoConversation.Operations
  alias JidoConversation.Projections
  alias JidoConversation.Telemetry, as: RuntimeTelemetry

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

  @doc """
  Returns aggregated runtime telemetry metrics.
  """
  @spec telemetry_snapshot() :: JidoConversation.Telemetry.metrics_snapshot()
  def telemetry_snapshot do
    RuntimeTelemetry.snapshot()
  end

  @doc """
  Replays conversation records from bus history, filtered by conversation id.
  """
  @spec replay_conversation(String.t(), keyword()) ::
          {:ok, [Jido.Signal.Bus.RecordedSignal.t()]} | {:error, term()}
  def replay_conversation(conversation_id, opts \\ []) do
    Operations.replay_conversation(conversation_id, opts)
  end

  @doc """
  Traces cause/effect links for a signal id.
  """
  @spec trace_cause_effect(String.t(), :forward | :backward) :: [Jido.Signal.t()]
  def trace_cause_effect(signal_id, direction \\ :backward) do
    Operations.trace_cause_effect(signal_id, direction)
  end

  @doc """
  Emits a `conv.audit.trace.chain_recorded` signal for a traced chain.
  """
  @spec record_audit_trace(String.t(), :forward | :backward, keyword()) ::
          {:ok, %{audit_signal: Jido.Signal.t(), trace: [Jido.Signal.t()]}}
          | {:error, JidoConversation.Ingest.Pipeline.ingest_error()}
  def record_audit_trace(signal_id, direction \\ :backward, opts \\ []) do
    Operations.record_audit_trace(signal_id, direction, opts)
  end

  @doc """
  Subscribes to a stream path on the conversation bus.
  """
  @spec subscribe_stream(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def subscribe_stream(path, opts \\ []) do
    Operations.subscribe_stream(path, opts)
  end

  @doc """
  Subscribes to a stream path and dispatches through Phoenix PubSub.
  """
  @spec subscribe_pubsub(String.t(), atom(), String.t(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def subscribe_pubsub(path, target, topic, opts \\ []) do
    Operations.subscribe_pubsub(path, target, topic, opts)
  end

  @doc """
  Subscribes to a stream path and dispatches through webhook delivery.
  """
  @spec subscribe_webhook(String.t(), String.t(), keyword(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def subscribe_webhook(path, url, subscribe_opts \\ [], webhook_opts \\ []) do
    Operations.subscribe_webhook(path, url, subscribe_opts, webhook_opts)
  end

  @doc """
  Unsubscribes from a stream subscription id.
  """
  @spec unsubscribe_stream(String.t(), keyword()) :: :ok | {:error, term()}
  def unsubscribe_stream(subscription_id, opts \\ []) do
    Operations.unsubscribe_stream(subscription_id, opts)
  end

  @doc """
  Lists stream subscriptions currently registered on the bus.
  """
  @spec stream_subscriptions() ::
          {:ok, [JidoConversation.Operations.subscription_summary()]} | {:error, term()}
  def stream_subscriptions do
    Operations.stream_subscriptions()
  end

  @doc """
  Inspects persistent subscription checkpoints and queue state.
  """
  @spec checkpoints() ::
          {:ok, [JidoConversation.Operations.checkpoint_summary()]} | {:error, term()}
  def checkpoints do
    Operations.checkpoints()
  end

  @doc """
  Lists in-flight signals for a persistent subscription.
  """
  @spec subscription_in_flight(String.t()) ::
          {:ok, [JidoConversation.Operations.in_flight_signal()]} | {:error, term()}
  def subscription_in_flight(subscription_id) do
    Operations.subscription_in_flight(subscription_id)
  end

  @doc """
  Acknowledges a specific signal log id for a persistent subscription.
  """
  @spec ack_stream(String.t(), String.t() | integer()) :: :ok | {:error, term()}
  def ack_stream(subscription_id, signal_log_id) do
    Operations.ack_stream(subscription_id, signal_log_id)
  end

  @doc """
  Lists DLQ entries for a subscription.
  """
  @spec dlq_entries(String.t()) :: {:ok, [map()]} | {:error, term()}
  def dlq_entries(subscription_id) do
    Operations.dlq_entries(subscription_id)
  end

  @doc """
  Re-drives DLQ entries for a subscription.
  """
  @spec redrive_dlq(String.t(), keyword()) ::
          {:ok, %{succeeded: integer(), failed: integer()}} | {:error, term()}
  def redrive_dlq(subscription_id, opts \\ []) do
    Operations.redrive_dlq(subscription_id, opts)
  end

  @doc """
  Clears DLQ entries for a subscription.
  """
  @spec clear_dlq(String.t()) :: :ok | {:error, term()}
  def clear_dlq(subscription_id) do
    Operations.clear_dlq(subscription_id)
  end

  @doc """
  Returns rollout migration counters and recent parity artifacts.
  """
  @spec rollout_snapshot() :: JidoConversation.Operations.rollout_snapshot()
  def rollout_snapshot do
    Operations.rollout_snapshot()
  end

  @doc """
  Resets rollout migration counters and parity artifacts.
  """
  @spec rollout_reset() :: :ok
  def rollout_reset do
    Operations.rollout_reset()
  end

  @doc """
  Compares `conv.out.*` outputs for a conversation with the configured legacy adapter.
  """
  @spec rollout_parity_compare(String.t(), keyword()) ::
          {:ok, JidoConversation.Rollout.Parity.parity_report()} | {:error, term()}
  def rollout_parity_compare(conversation_id, opts \\ []) do
    Operations.rollout_parity_compare(conversation_id, opts)
  end

  @doc """
  Evaluates rollout acceptance status from rollout counters and parity reports.
  """
  @spec rollout_verify(keyword()) :: JidoConversation.Rollout.Verification.report()
  def rollout_verify(opts \\ []) do
    Operations.rollout_verify(opts)
  end
end
