defmodule JidoConversation.Operations do
  @moduledoc """
  Operator-facing replay, trace, subscription, and checkpoint tooling.
  """

  alias Jido.Signal
  alias Jido.Signal.Bus
  alias Jido.Signal.Bus.RecordedSignal
  alias JidoConversation.Config
  alias JidoConversation.Ingest

  @type subscription_summary :: %{
          subscription_id: String.t(),
          path: String.t(),
          persistent?: boolean(),
          disconnected?: boolean(),
          dispatch: atom(),
          created_at: DateTime.t() | nil
        }

  @type checkpoint_summary :: %{
          subscription_id: String.t(),
          checkpoint: non_neg_integer() | nil,
          in_flight_count: non_neg_integer(),
          pending_count: non_neg_integer(),
          attempts_count: non_neg_integer(),
          max_in_flight: pos_integer() | nil,
          max_pending: pos_integer() | nil,
          max_attempts: pos_integer() | nil,
          retry_interval: pos_integer() | nil
        }

  @spec replay_conversation(String.t(), keyword()) ::
          {:ok, [RecordedSignal.t()]} | {:error, term()}
  def replay_conversation(conversation_id, opts \\ [])
      when is_binary(conversation_id) and is_list(opts) do
    path = Keyword.get(opts, :path, "conv.**")
    start_timestamp = Keyword.get(opts, :start_timestamp, 0)
    replay_opts = Keyword.get(opts, :replay_opts, [])
    limit = Keyword.get(opts, :limit)

    with {:ok, recorded} <- Ingest.replay(path, start_timestamp, replay_opts) do
      filtered =
        recorded
        |> Enum.filter(&(subject_for_recorded(&1) == conversation_id))
        |> maybe_limit(limit)

      {:ok, filtered}
    end
  end

  @spec trace_cause_effect(String.t(), :forward | :backward) :: [Signal.t()]
  def trace_cause_effect(signal_id, direction \\ :backward)
      when is_binary(signal_id) and direction in [:forward, :backward] do
    Ingest.trace_chain(signal_id, direction)
  end

  @spec record_audit_trace(String.t(), :forward | :backward, keyword()) ::
          {:ok, %{audit_signal: Signal.t(), trace: [Signal.t()]}}
          | {:error, JidoConversation.Ingest.Pipeline.ingest_error()}
  def record_audit_trace(signal_id, direction \\ :backward, opts \\ [])
      when is_binary(signal_id) and direction in [:forward, :backward] and is_list(opts) do
    trace = trace_cause_effect(signal_id, direction)
    subject = Keyword.get(opts, :subject, infer_subject(trace))
    audit_id = Keyword.get(opts, :audit_id, "audit-#{System.unique_integer([:positive])}")
    category = Keyword.get(opts, :category, "causality_trace")

    attrs = %{
      type: "conv.audit.trace.chain_recorded",
      source: "/operations/trace",
      subject: subject,
      data: %{
        audit_id: audit_id,
        category: category,
        trace_direction: Atom.to_string(direction),
        trace_length: length(trace),
        trace_signal_id: signal_id,
        trace_signal_ids: Enum.map(trace, & &1.id)
      },
      extensions: %{"contract_major" => 1}
    }

    with {:ok, %{signal: audit_signal}} <- ingest_audit_with_cause(attrs, signal_id) do
      {:ok, %{audit_signal: audit_signal, trace: trace}}
    end
  end

  @spec subscribe_stream(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def subscribe_stream(path, opts \\ []) when is_binary(path) and is_list(opts) do
    Bus.subscribe(Config.bus_name(), path, opts)
  end

  @spec subscribe_pubsub(String.t(), atom(), String.t(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def subscribe_pubsub(path, target, topic, opts \\ [])
      when is_binary(path) and is_atom(target) and is_binary(topic) and is_list(opts) do
    subscribe_stream(path, Keyword.put(opts, :dispatch, {:pubsub, target: target, topic: topic}))
  end

  @spec subscribe_webhook(String.t(), String.t(), keyword(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def subscribe_webhook(path, url, subscribe_opts \\ [], webhook_opts \\ [])
      when is_binary(path) and is_binary(url) and is_list(subscribe_opts) and
             is_list(webhook_opts) do
    dispatch = {:webhook, Keyword.merge([url: url], webhook_opts)}
    subscribe_stream(path, Keyword.put(subscribe_opts, :dispatch, dispatch))
  end

  @spec unsubscribe_stream(String.t(), keyword()) :: :ok | {:error, term()}
  def unsubscribe_stream(subscription_id, opts \\ [])
      when is_binary(subscription_id) and is_list(opts) do
    Bus.unsubscribe(Config.bus_name(), subscription_id, opts)
  end

  @spec stream_subscriptions() :: {:ok, [subscription_summary()]} | {:error, term()}
  def stream_subscriptions do
    with {:ok, bus_pid} <- Bus.whereis(Config.bus_name()) do
      subscriptions =
        bus_pid
        |> :sys.get_state()
        |> Map.get(:subscriptions, %{})
        |> normalize_subscriptions()

      summaries =
        subscriptions
        |> Enum.map(fn {subscription_id, subscription} ->
          %{
            subscription_id: subscription_id,
            path: Map.get(subscription, :path),
            persistent?: Map.get(subscription, :persistent?, false),
            disconnected?: Map.get(subscription, :disconnected?, false),
            dispatch: dispatch_adapter(Map.get(subscription, :dispatch)),
            created_at: Map.get(subscription, :created_at)
          }
        end)
        |> Enum.sort_by(& &1.subscription_id)

      {:ok, summaries}
    end
  end

  @spec checkpoints() :: {:ok, [checkpoint_summary()]} | {:error, term()}
  def checkpoints do
    with {:ok, bus_pid} <- Bus.whereis(Config.bus_name()) do
      checkpoints =
        bus_pid
        |> :sys.get_state()
        |> Map.get(:subscriptions, %{})
        |> normalize_subscriptions()
        |> Enum.flat_map(fn {subscription_id, subscription} ->
          checkpoint_for_subscription(subscription_id, subscription)
        end)
        |> Enum.sort_by(& &1.subscription_id)

      {:ok, checkpoints}
    end
  end

  defp normalize_subscriptions(subscriptions) when is_map(subscriptions), do: subscriptions
  defp normalize_subscriptions(_subscriptions), do: %{}

  defp checkpoint_for_subscription(_subscription_id, %{persistent?: false}), do: []

  defp checkpoint_for_subscription(subscription_id, %{persistent?: true, persistence_pid: pid})
       when is_pid(pid) do
    if Process.alive?(pid) do
      state = :sys.get_state(pid)

      [
        %{
          subscription_id: subscription_id,
          checkpoint: Map.get(state, :checkpoint),
          in_flight_count: map_size_or_zero(Map.get(state, :in_flight_signals)),
          pending_count: map_size_or_zero(Map.get(state, :pending_signals)),
          attempts_count: map_size_or_zero(Map.get(state, :attempts)),
          max_in_flight: Map.get(state, :max_in_flight),
          max_pending: Map.get(state, :max_pending),
          max_attempts: Map.get(state, :max_attempts),
          retry_interval: Map.get(state, :retry_interval)
        }
      ]
    else
      checkpoint_for_subscription(subscription_id, %{persistent?: true})
    end
  end

  defp checkpoint_for_subscription(subscription_id, %{persistent?: true}) do
    [
      %{
        subscription_id: subscription_id,
        checkpoint: nil,
        in_flight_count: 0,
        pending_count: 0,
        attempts_count: 0,
        max_in_flight: nil,
        max_pending: nil,
        max_attempts: nil,
        retry_interval: nil
      }
    ]
  end

  defp checkpoint_for_subscription(_subscription_id, _subscription), do: []

  defp map_size_or_zero(map) when is_map(map), do: map_size(map)
  defp map_size_or_zero(_other), do: 0

  defp dispatch_adapter({adapter, _opts}) when is_atom(adapter), do: adapter
  defp dispatch_adapter(_dispatch), do: :unknown

  defp subject_for_recorded(%RecordedSignal{signal: %Signal{subject: subject}}), do: subject
  defp subject_for_recorded(_recorded), do: nil

  defp maybe_limit(entries, limit) when is_integer(limit) and limit > 0 do
    Enum.take(entries, limit)
  end

  defp maybe_limit(entries, _limit), do: entries

  defp infer_subject(trace) when is_list(trace) do
    trace
    |> Enum.find_value(fn
      %Signal{subject: subject} when is_binary(subject) and subject != "" -> subject
      _ -> nil
    end) || "audit"
  end

  defp ingest_audit_with_cause(attrs, cause_id) do
    case Ingest.ingest(attrs, cause_id: cause_id) do
      {:ok, _result} = ok ->
        ok

      {:error, {:journal_record_failed, :cause_not_found}} ->
        Ingest.ingest(attrs)

      {:error, {:invalid_cause_id, _reason}} ->
        Ingest.ingest(attrs)

      {:error, _reason} = error ->
        error
    end
  end
end
