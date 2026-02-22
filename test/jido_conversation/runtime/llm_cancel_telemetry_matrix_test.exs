defmodule Jido.Conversation.Runtime.LLMCancelTelemetryMatrixTest do
  use ExUnit.Case, async: false

  alias Jido.Conversation.Ingest
  alias Jido.Conversation.Runtime.Coordinator
  alias Jido.Conversation.Runtime.EffectManager
  alias Jido.Conversation.Runtime.IngressSubscriber
  alias Jido.Conversation.Telemetry

  @app :jido_conversation
  @key Jido.Conversation.EventSystem

  defmodule CancelTelemetryBackendStub do
    @behaviour Jido.Conversation.LLM.Backend

    alias Jido.Conversation.LLM.Error
    alias Jido.Conversation.LLM.Event
    alias Jido.Conversation.LLM.Request
    alias Jido.Conversation.LLM.Result

    @impl true
    def capabilities do
      %{
        streaming?: true,
        cancellation?: true,
        provider_selection?: true,
        model_selection?: true
      }
    end

    @impl true
    def start(%Request{} = request, _opts) do
      {:ok,
       Result.new!(%{
         request_id: request.request_id,
         conversation_id: request.conversation_id,
         backend: request.backend,
         status: :completed,
         text: "start-completed"
       })}
    end

    @impl true
    def stream(%Request{} = request, emit, opts) when is_function(emit, 1) do
      test_pid = Keyword.get(opts, :test_pid, self())
      include_execution_ref? = Keyword.get(opts, :include_execution_ref?, true)
      execution_ref = if include_execution_ref?, do: self(), else: nil

      send(test_pid, {:cancel_matrix_stream_started, request.backend, execution_ref})

      _ =
        emit.(
          Event.new!(%{
            request_id: request.request_id,
            conversation_id: request.conversation_id,
            backend: request.backend,
            lifecycle: :started,
            provider: request.provider || "matrix-provider",
            model: request.model || "matrix-model",
            metadata: metadata_for_execution_ref(execution_ref)
          })
        )

      receive do
        :cancel ->
          {:error, Error.new!(category: :canceled, message: "canceled", retryable?: false)}
      after
        5_000 ->
          {:ok,
           Result.new!(%{
             request_id: request.request_id,
             conversation_id: request.conversation_id,
             backend: request.backend,
             status: :completed,
             text: "unexpected completion"
           })}
      end
    end

    @impl true
    def cancel(execution_ref, opts) do
      test_pid = Keyword.get(opts, :test_pid, self())
      scenario = Keyword.get(opts, :cancel_scenario, :ok)
      send(test_pid, {:cancel_matrix_cancel_called, scenario, execution_ref})

      case scenario do
        :ok ->
          if is_pid(execution_ref), do: send(execution_ref, :cancel)
          :ok

        :failed ->
          {:error, Error.new!(category: :provider, message: "cancel failed", retryable?: true)}
      end
    end

    defp metadata_for_execution_ref(nil), do: %{}
    defp metadata_for_execution_ref(execution_ref), do: %{execution_ref: execution_ref}
  end

  setup do
    previous = Application.get_env(@app, @key)

    wait_for_ingress_subscriber!()
    wait_for_runtime_idle!()

    on_exit(fn ->
      if is_nil(previous) do
        Application.delete_env(@app, @key)
      else
        Application.put_env(@app, @key, previous)
      end

      wait_for_runtime_idle!()
    end)

    :ok
  end

  test "cancel telemetry records ok result across backends when backend cancellation succeeds" do
    Enum.each([:jido_ai, :harness], fn backend ->
      :ok = Telemetry.reset()
      baseline = Telemetry.snapshot().llm

      put_runtime_backend!(backend,
        include_execution_ref?: true,
        cancel_scenario: :ok,
        test_pid: self()
      )

      conversation_id = unique_id("cancel-ok-conversation-#{backend}")
      effect_id = unique_id("cancel-ok-effect-#{backend}")
      replay_start = DateTime.utc_now() |> DateTime.to_unix()

      :ok =
        EffectManager.start_effect(
          %{
            effect_id: effect_id,
            conversation_id: conversation_id,
            class: :llm,
            kind: "generation",
            input: %{content: "cancel me"},
            policy: %{max_attempts: 1, backoff_ms: 5, timeout_ms: 1_000}
          },
          nil
        )

      assert_receive {:cancel_matrix_stream_started, ^backend, execution_ref}
      assert is_pid(execution_ref)

      :ok = EffectManager.cancel_conversation(conversation_id, "user_abort", nil)
      assert_receive {:cancel_matrix_cancel_called, :ok, ^execution_ref}

      assert_canceled_without_completion!(effect_id, replay_start)

      snapshot =
        eventually(fn ->
          llm = Telemetry.snapshot().llm

          if llm.lifecycle_counts.canceled >= baseline.lifecycle_counts.canceled + 1 and
               llm.cancel_latency_ms.count >= baseline.cancel_latency_ms.count + 1 and
               llm_cancel_result_count(llm.cancel_results, "ok") >=
                 llm_cancel_result_count(baseline.cancel_results, "ok") + 1 do
            {:ok, llm}
          else
            :retry
          end
        end)

      assert llm_cancel_result_count(snapshot.cancel_results, "ok") >=
               llm_cancel_result_count(baseline.cancel_results, "ok") + 1

      assert backend_lifecycle_count(
               snapshot.lifecycle_by_backend,
               Atom.to_string(backend),
               :canceled
             ) >=
               backend_lifecycle_count(
                 baseline.lifecycle_by_backend,
                 Atom.to_string(backend),
                 :canceled
               ) +
                 1
    end)
  end

  test "cancel telemetry records not_available result across backends when execution_ref is missing" do
    Enum.each([:jido_ai, :harness], fn backend ->
      :ok = Telemetry.reset()
      baseline = Telemetry.snapshot().llm

      put_runtime_backend!(backend,
        include_execution_ref?: false,
        cancel_scenario: :ok,
        test_pid: self()
      )

      conversation_id = unique_id("cancel-na-conversation-#{backend}")
      effect_id = unique_id("cancel-na-effect-#{backend}")
      replay_start = DateTime.utc_now() |> DateTime.to_unix()

      :ok =
        EffectManager.start_effect(
          %{
            effect_id: effect_id,
            conversation_id: conversation_id,
            class: :llm,
            kind: "generation",
            input: %{content: "cancel me without execution ref"},
            policy: %{max_attempts: 1, backoff_ms: 5, timeout_ms: 1_000}
          },
          nil
        )

      assert_receive {:cancel_matrix_stream_started, ^backend, nil}

      :ok = EffectManager.cancel_conversation(conversation_id, "user_abort", nil)
      refute_receive {:cancel_matrix_cancel_called, _, _}, 200

      assert_canceled_without_completion!(effect_id, replay_start)

      snapshot =
        eventually(fn ->
          llm = Telemetry.snapshot().llm

          if llm.lifecycle_counts.canceled >= baseline.lifecycle_counts.canceled + 1 and
               llm.cancel_latency_ms.count >= baseline.cancel_latency_ms.count + 1 and
               llm_cancel_result_count(llm.cancel_results, "not_available") >=
                 llm_cancel_result_count(baseline.cancel_results, "not_available") + 1 do
            {:ok, llm}
          else
            :retry
          end
        end)

      assert llm_cancel_result_count(snapshot.cancel_results, "not_available") >=
               llm_cancel_result_count(baseline.cancel_results, "not_available") + 1
    end)
  end

  test "cancel telemetry records failed result across backends when backend cancellation fails" do
    Enum.each([:jido_ai, :harness], fn backend ->
      :ok = Telemetry.reset()
      baseline = Telemetry.snapshot().llm

      put_runtime_backend!(backend,
        include_execution_ref?: true,
        cancel_scenario: :failed,
        test_pid: self()
      )

      conversation_id = unique_id("cancel-failed-conversation-#{backend}")
      effect_id = unique_id("cancel-failed-effect-#{backend}")
      replay_start = DateTime.utc_now() |> DateTime.to_unix()

      :ok =
        EffectManager.start_effect(
          %{
            effect_id: effect_id,
            conversation_id: conversation_id,
            class: :llm,
            kind: "generation",
            input: %{content: "cancel me with backend failure"},
            policy: %{max_attempts: 1, backoff_ms: 5, timeout_ms: 1_000}
          },
          nil
        )

      assert_receive {:cancel_matrix_stream_started, ^backend, execution_ref}
      assert is_pid(execution_ref)

      :ok = EffectManager.cancel_conversation(conversation_id, "user_abort", nil)
      assert_receive {:cancel_matrix_cancel_called, :failed, ^execution_ref}

      assert_canceled_without_completion!(effect_id, replay_start)

      snapshot =
        eventually(fn ->
          llm = Telemetry.snapshot().llm

          if llm.lifecycle_counts.canceled >= baseline.lifecycle_counts.canceled + 1 and
               llm.cancel_latency_ms.count >= baseline.cancel_latency_ms.count + 1 and
               llm_cancel_result_count(llm.cancel_results, "failed") >=
                 llm_cancel_result_count(baseline.cancel_results, "failed") + 1 do
            {:ok, llm}
          else
            :retry
          end
        end)

      assert llm_cancel_result_count(snapshot.cancel_results, "failed") >=
               llm_cancel_result_count(baseline.cancel_results, "failed") + 1
    end)
  end

  defp put_runtime_backend!(backend, opts)
       when backend in [:jido_ai, :harness] and is_list(opts) do
    timeout_ms = 1_000
    include_execution_ref? = Keyword.get(opts, :include_execution_ref?, true)
    cancel_scenario = Keyword.get(opts, :cancel_scenario, :ok)
    test_pid = Keyword.fetch!(opts, :test_pid)

    backend_opts = [
      include_execution_ref?: include_execution_ref?,
      cancel_scenario: cancel_scenario,
      test_pid: test_pid
    ]

    jido_ai_cfg =
      if backend == :jido_ai do
        [
          module: CancelTelemetryBackendStub,
          stream?: true,
          timeout_ms: timeout_ms,
          provider: "matrix-provider",
          model: "matrix-model",
          options: backend_opts
        ]
      else
        [
          module: nil,
          stream?: true,
          timeout_ms: timeout_ms,
          provider: nil,
          model: nil,
          options: []
        ]
      end

    harness_cfg =
      if backend == :harness do
        [
          module: CancelTelemetryBackendStub,
          stream?: true,
          timeout_ms: timeout_ms,
          provider: "codex",
          model: "matrix-model",
          options: backend_opts
        ]
      else
        [
          module: nil,
          stream?: true,
          timeout_ms: timeout_ms,
          provider: nil,
          model: nil,
          options: []
        ]
      end

    Application.put_env(@app, @key,
      llm: [
        default_backend: backend,
        default_stream?: true,
        default_timeout_ms: timeout_ms,
        default_provider: nil,
        default_model: nil,
        backends: [
          jido_ai: jido_ai_cfg,
          harness: harness_cfg
        ]
      ]
    )
  end

  defp assert_canceled_without_completion!(effect_id, replay_start) do
    events = eventually(fn -> canceled_effect_events(effect_id, replay_start) end)

    assert Enum.any?(events, &(lifecycle_for(&1) == "canceled"))
    refute Enum.any?(events, &(lifecycle_for(&1) == "completed"))
  end

  defp canceled_effect_events(effect_id, replay_start) do
    case Ingest.replay("conv.effect.llm.generation.**", replay_start) do
      {:ok, records} ->
        matches = Enum.filter(records, &(effect_id_for(&1) == effect_id))

        if Enum.any?(matches, &(lifecycle_for(&1) == "canceled")) do
          {:ok, matches}
        else
          :retry
        end

      _other ->
        :retry
    end
  end

  defp llm_cancel_result_count(cancel_results, key)
       when is_map(cancel_results) and is_binary(key) do
    Map.get(cancel_results, key, 0)
  end

  defp backend_lifecycle_count(lifecycle_by_backend, backend, lifecycle)
       when is_map(lifecycle_by_backend) and is_binary(backend) and is_atom(lifecycle) do
    lifecycle_by_backend
    |> Map.get(backend, %{})
    |> Map.get(lifecycle, 0)
  end

  defp eventually(fun, attempts \\ 250)
  defp eventually(_fun, 0), do: raise("condition not met within timeout")

  defp eventually(fun, attempts) do
    case fun.() do
      {:ok, result} ->
        result

      :retry ->
        Process.sleep(20)
        eventually(fun, attempts - 1)
    end
  end

  defp lifecycle_for(record), do: data_field(record, :lifecycle, "")
  defp effect_id_for(record), do: data_field(record, :effect_id, nil)

  defp data_field(record, key, default) do
    data = record.signal.data || %{}

    case Map.fetch(data, key) do
      {:ok, value} ->
        value

      :error ->
        Map.get(data, to_string(key), default)
    end
  end

  defp unique_id(prefix) do
    "#{prefix}-#{System.unique_integer([:positive, :monotonic])}"
  end

  defp wait_for_ingress_subscriber! do
    eventually(fn ->
      case :sys.get_state(IngressSubscriber) do
        %{subscription_id: subscription_id} when is_binary(subscription_id) ->
          {:ok, :ready}

        _ ->
          :retry
      end
    end)
  end

  defp wait_for_runtime_idle! do
    eventually(fn ->
      coordinator_stats = Coordinator.stats()
      effect_stats = EffectManager.stats()

      partition_busy? =
        coordinator_stats.partitions
        |> Map.values()
        |> Enum.any?(fn partition ->
          partition.queue_size > 0
        end)

      if partition_busy? or effect_stats.in_flight_count > 0 do
        :retry
      else
        {:ok, :ready}
      end
    end)
  end
end
