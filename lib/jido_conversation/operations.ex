defmodule JidoConversation.Operations do
  @moduledoc """
  Operator-facing replay, trace, subscription, checkpoint, and readiness tooling.
  """

  alias Jido.Signal
  alias Jido.Signal.Bus
  alias Jido.Signal.Bus.RecordedSignal
  alias JidoConversation.Config
  alias JidoConversation.Health
  alias JidoConversation.Ingest
  alias JidoConversation.Telemetry

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

  @type in_flight_signal :: %{
          signal_log_id: String.t(),
          signal_id: String.t(),
          signal_type: String.t(),
          subject: String.t() | nil
        }

  @type readiness_severity :: :critical | :warning
  @type readiness_status :: :ready | :warning | :not_ready

  @type readiness_issue :: %{
          check: :health | :telemetry | :subscriptions | :checkpoints | :dlq,
          severity: readiness_severity(),
          message: String.t(),
          details: map()
        }

  @type launch_readiness_report :: %{
          status: readiness_status(),
          checked_at: DateTime.t(),
          health: Health.status_map(),
          telemetry: Telemetry.metrics_snapshot(),
          subscriptions: %{
            total: non_neg_integer(),
            persistent: non_neg_integer(),
            disconnected: non_neg_integer()
          },
          checkpoints: %{
            total: non_neg_integer(),
            saturated: non_neg_integer()
          },
          dlq: %{
            subscriptions_with_entries: non_neg_integer(),
            total_entries: non_neg_integer()
          },
          issues: [readiness_issue()]
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

  @spec ack_stream(String.t(), String.t() | integer()) :: :ok | {:error, term()}
  def ack_stream(subscription_id, signal_log_id)
      when is_binary(subscription_id) and (is_binary(signal_log_id) or is_integer(signal_log_id)) do
    Bus.ack(Config.bus_name(), subscription_id, signal_log_id)
  end

  @spec subscription_in_flight(String.t()) :: {:ok, [in_flight_signal()]} | {:error, term()}
  def subscription_in_flight(subscription_id) when is_binary(subscription_id) do
    with {:ok, bus_pid} <- Bus.whereis(Config.bus_name()),
         {:ok, subscription} <- fetch_subscription(bus_pid, subscription_id),
         {:ok, persistence_pid} <- fetch_persistence_pid(subscription),
         true <- Process.alive?(persistence_pid) do
      in_flight =
        persistence_pid
        |> :sys.get_state()
        |> Map.get(:in_flight_signals, %{})
        |> Enum.map(fn {signal_log_id, signal} ->
          %{
            signal_log_id: signal_log_id,
            signal_id: signal.id,
            signal_type: signal.type,
            subject: signal.subject
          }
        end)
        |> Enum.sort_by(& &1.signal_log_id)

      {:ok, in_flight}
    else
      false -> {:error, :persistence_not_alive}
      {:error, _reason} = error -> error
    end
  end

  @spec dlq_entries(String.t()) :: {:ok, [map()]} | {:error, term()}
  def dlq_entries(subscription_id) when is_binary(subscription_id) do
    Bus.dlq_entries(Config.bus_name(), subscription_id)
  end

  @spec redrive_dlq(String.t(), keyword()) ::
          {:ok, %{succeeded: integer(), failed: integer()}} | {:error, term()}
  def redrive_dlq(subscription_id, opts \\ [])
      when is_binary(subscription_id) and is_list(opts) do
    Bus.redrive_dlq(Config.bus_name(), subscription_id, opts)
  end

  @spec clear_dlq(String.t()) :: :ok | {:error, term()}
  def clear_dlq(subscription_id) when is_binary(subscription_id) do
    Bus.clear_dlq(Config.bus_name(), subscription_id)
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

  @spec launch_readiness(keyword()) :: {:ok, launch_readiness_report()}
  def launch_readiness(opts \\ []) when is_list(opts) do
    max_queue_depth = non_neg_or_default(Keyword.get(opts, :max_queue_depth), 1_000)
    max_dispatch_failures = non_neg_or_default(Keyword.get(opts, :max_dispatch_failures), 0)

    health = Health.status()
    telemetry = Telemetry.snapshot()

    {subscriptions, subscription_issues} = fetch_subscriptions_for_readiness()
    {checkpoint_entries, checkpoint_issues} = fetch_checkpoints_for_readiness()
    {dlq_summary, dlq_issues} = summarize_dlq(subscriptions)

    issues =
      []
      |> maybe_add_health_issue(health)
      |> maybe_add_queue_depth_issue(telemetry, max_queue_depth)
      |> maybe_add_dispatch_failure_issue(telemetry, max_dispatch_failures)
      |> Kernel.++(subscription_issues)
      |> Kernel.++(checkpoint_issues)
      |> Kernel.++(subscription_state_issues(subscriptions))
      |> Kernel.++(checkpoint_state_issues(checkpoint_entries))
      |> Kernel.++(dlq_issues)

    report = %{
      status: readiness_status(issues),
      checked_at: DateTime.utc_now(),
      health: health,
      telemetry: telemetry,
      subscriptions: summarize_subscriptions(subscriptions),
      checkpoints: summarize_checkpoints(checkpoint_entries),
      dlq: dlq_summary,
      issues: issues
    }

    {:ok, report}
  end

  defp normalize_subscriptions(subscriptions) when is_map(subscriptions), do: subscriptions
  defp normalize_subscriptions(_subscriptions), do: %{}

  defp fetch_subscription(bus_pid, subscription_id) when is_pid(bus_pid) do
    subscriptions =
      bus_pid
      |> :sys.get_state()
      |> Map.get(:subscriptions, %{})
      |> normalize_subscriptions()

    case Map.get(subscriptions, subscription_id) do
      nil -> {:error, :subscription_not_found}
      subscription -> {:ok, subscription}
    end
  end

  defp fetch_persistence_pid(subscription) do
    if Map.get(subscription, :persistent?, false) do
      case Map.get(subscription, :persistence_pid) do
        pid when is_pid(pid) -> {:ok, pid}
        _other -> {:error, :subscription_not_persistent}
      end
    else
      {:error, :subscription_not_persistent}
    end
  end

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

  defp fetch_subscriptions_for_readiness do
    case stream_subscriptions() do
      {:ok, subscriptions} ->
        {subscriptions, []}

      {:error, reason} ->
        issue = %{
          check: :subscriptions,
          severity: :critical,
          message: "Unable to load stream subscriptions",
          details: %{reason: inspect(reason)}
        }

        {[], [issue]}
    end
  end

  defp fetch_checkpoints_for_readiness do
    case checkpoints() do
      {:ok, checkpoint_entries} ->
        {checkpoint_entries, []}

      {:error, reason} ->
        issue = %{
          check: :checkpoints,
          severity: :critical,
          message: "Unable to load persistent subscription checkpoints",
          details: %{reason: inspect(reason)}
        }

        {[], [issue]}
    end
  end

  defp summarize_subscriptions(subscriptions) do
    %{
      total: length(subscriptions),
      persistent: Enum.count(subscriptions, & &1.persistent?),
      disconnected: Enum.count(subscriptions, & &1.disconnected?)
    }
  end

  defp summarize_checkpoints(checkpoint_entries) do
    %{
      total: length(checkpoint_entries),
      saturated: Enum.count(checkpoint_entries, &saturated_checkpoint?/1)
    }
  end

  defp summarize_dlq(subscriptions) do
    {summary, issues} =
      Enum.reduce(
        subscriptions,
        {%{subscriptions_with_entries: 0, total_entries: 0}, []},
        fn subscription, {acc, acc_issues} ->
          case dlq_entries(subscription.subscription_id) do
            {:ok, entries} ->
              {update_dlq_summary(acc, length(entries)), acc_issues}

            {:error, reason} ->
              issue = %{
                check: :dlq,
                severity: :critical,
                message: "Unable to load DLQ entries for subscription",
                details: %{
                  subscription_id: subscription.subscription_id,
                  reason: inspect(reason)
                }
              }

              {acc, acc_issues ++ [issue]}
          end
        end
      )

    dlq_warning_issues =
      if summary.total_entries > 0 do
        [
          %{
            check: :dlq,
            severity: :warning,
            message: "DLQ entries present",
            details: summary
          }
        ]
      else
        []
      end

    {summary, issues ++ dlq_warning_issues}
  end

  defp update_dlq_summary(acc, entry_count) when entry_count > 0 do
    %{
      subscriptions_with_entries: acc.subscriptions_with_entries + 1,
      total_entries: acc.total_entries + entry_count
    }
  end

  defp update_dlq_summary(acc, _entry_count), do: acc

  defp maybe_add_health_issue(issues, %{status: :ok}), do: issues

  defp maybe_add_health_issue(issues, health) do
    issues ++
      [
        %{
          check: :health,
          severity: :critical,
          message: "Runtime health is degraded",
          details: health
        }
      ]
  end

  defp maybe_add_queue_depth_issue(issues, telemetry, max_queue_depth) do
    queue_depth = telemetry.queue_depth.total

    if queue_depth > max_queue_depth do
      issues ++
        [
          %{
            check: :telemetry,
            severity: :warning,
            message: "Queue depth exceeds launch readiness threshold",
            details: %{queue_depth: queue_depth, max_queue_depth: max_queue_depth}
          }
        ]
    else
      issues
    end
  end

  defp maybe_add_dispatch_failure_issue(issues, telemetry, max_dispatch_failures) do
    dispatch_failure_count = telemetry.dispatch_failure_count

    if dispatch_failure_count > max_dispatch_failures do
      issues ++
        [
          %{
            check: :telemetry,
            severity: :warning,
            message: "Dispatch failures exceed launch readiness threshold",
            details: %{
              dispatch_failure_count: dispatch_failure_count,
              max_dispatch_failures: max_dispatch_failures
            }
          }
        ]
    else
      issues
    end
  end

  defp subscription_state_issues(subscriptions) do
    disconnected = Enum.count(subscriptions, & &1.disconnected?)

    if disconnected > 0 do
      [
        %{
          check: :subscriptions,
          severity: :warning,
          message: "Disconnected subscriptions detected",
          details: %{disconnected: disconnected}
        }
      ]
    else
      []
    end
  end

  defp checkpoint_state_issues(checkpoint_entries) do
    saturated = Enum.count(checkpoint_entries, &saturated_checkpoint?/1)

    if saturated > 0 do
      [
        %{
          check: :checkpoints,
          severity: :warning,
          message: "Persistent subscriptions are at saturation limits",
          details: %{saturated: saturated}
        }
      ]
    else
      []
    end
  end

  defp saturated_checkpoint?(checkpoint) do
    reached_or_exceeded?(checkpoint.in_flight_count, checkpoint.max_in_flight) or
      reached_or_exceeded?(checkpoint.pending_count, checkpoint.max_pending)
  end

  defp reached_or_exceeded?(_count, nil), do: false
  defp reached_or_exceeded?(count, limit) when is_integer(limit), do: count >= limit

  defp readiness_status(issues) do
    cond do
      Enum.any?(issues, &(&1.severity == :critical)) ->
        :not_ready

      issues == [] ->
        :ready

      true ->
        :warning
    end
  end

  defp non_neg_or_default(value, _default) when is_integer(value) and value >= 0, do: value
  defp non_neg_or_default(_value, default), do: default

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
