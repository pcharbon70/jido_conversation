defmodule JidoConversation.Runtime.LLMCancelTelemetryMatrixTest do
  use ExUnit.Case, async: false

  alias JidoConversation.Ingest
  alias JidoConversation.Runtime.Coordinator
  alias JidoConversation.Runtime.EffectManager
  alias JidoConversation.Runtime.IngressSubscriber
  alias JidoConversation.Telemetry

  @app :jido_conversation
  @key JidoConversation.EventSystem
  @assert_timeout 1_000

  defmodule CancelTelemetryBackendStub do
    @behaviour JidoConversation.LLM.Backend

    alias JidoConversation.LLM.Error
    alias JidoConversation.LLM.Event
    alias JidoConversation.LLM.Request
    alias JidoConversation.LLM.Result

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

      assert_receive {:cancel_matrix_stream_started, ^backend, execution_ref}, @assert_timeout
      assert is_pid(execution_ref)
      Process.sleep(50)

      :ok = EffectManager.cancel_conversation(conversation_id, "user_abort", nil)
      assert_receive {:cancel_matrix_cancel_called, :ok, ^execution_ref}, @assert_timeout

      canceled_event =
        eventually(fn ->
          case Ingest.replay("conv.effect.llm.generation.canceled", replay_start) do
            {:ok, records} ->
              records
              |> Enum.find(fn record ->
                effect_id_for(record) == effect_id and lifecycle_for(record) == "canceled"
              end)
              |> case do
                nil -> :retry
                event -> {:ok, event}
              end

            _other ->
              :retry
          end
        end)

      assert data_field(canceled_event, :reason, nil) == "user_abort"
      assert data_field(canceled_event, :backend_cancel, nil) == "ok"
      assert data_field(canceled_event, :backend, nil) == Atom.to_string(backend)
      assert data_field(canceled_event, :model, nil) == "matrix-model"

      expected_provider =
        case backend do
          :jido_ai -> "matrix-provider"
          :harness -> "codex"
        end

      assert data_field(canceled_event, :provider, nil) == expected_provider
      assert_terminal_canceled_only!(effect_id, replay_start)

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

      assert snapshot.retry_by_category == baseline.retry_by_category
    end)
  end

  test "ok cancel with explicit cause_id links canceled lifecycle across backends" do
    Enum.each([:jido_ai, :harness], fn backend ->
      :ok = Telemetry.reset()
      baseline = Telemetry.snapshot().llm

      put_runtime_backend!(backend,
        include_execution_ref?: true,
        cancel_scenario: :ok,
        test_pid: self()
      )

      conversation_id = unique_id("cancel-ok-cause-link-conversation-#{backend}")
      effect_id = unique_id("cancel-ok-cause-link-effect-#{backend}")
      replay_start = DateTime.utc_now() |> DateTime.to_unix()

      assert {:ok, %{signal: cause_signal}} =
               Ingest.ingest(%{
                 id: unique_id("cancel-ok-cause-link-cause-#{backend}"),
                 type: "conv.audit.policy.decision_recorded",
                 source: "/tests/llm-cancel-telemetry-matrix",
                 subject: conversation_id,
                 data: %{
                   audit_id: unique_id("cancel-ok-cause-link-audit-#{backend}"),
                   category: "policy",
                   decision: "allow"
                 },
                 extensions: %{contract_major: 1}
               })

      :ok =
        EffectManager.start_effect(
          %{
            effect_id: effect_id,
            conversation_id: conversation_id,
            class: :llm,
            kind: "generation",
            input: %{content: "cancel me with explicit cause"},
            policy: %{max_attempts: 1, backoff_ms: 5, timeout_ms: 1_000}
          },
          nil
        )

      assert_receive {:cancel_matrix_stream_started, ^backend, execution_ref}, @assert_timeout
      assert is_pid(execution_ref)
      Process.sleep(50)

      :ok = EffectManager.cancel_conversation(conversation_id, "user_abort", cause_signal.id)
      assert_receive {:cancel_matrix_cancel_called, :ok, ^execution_ref}, @assert_timeout

      canceled_event =
        eventually(fn ->
          case Ingest.replay("conv.effect.llm.generation.canceled", replay_start) do
            {:ok, records} ->
              records
              |> Enum.find(fn record ->
                effect_id_for(record) == effect_id and lifecycle_for(record) == "canceled"
              end)
              |> case do
                nil -> :retry
                event -> {:ok, event}
              end

            _other ->
              :retry
          end
        end)

      assert data_field(canceled_event, :reason, nil) == "user_abort"
      assert data_field(canceled_event, :backend_cancel, nil) == "ok"

      trace = Ingest.trace_chain(canceled_event.signal.id, :backward)
      trace_ids = Enum.map(trace, & &1.id)

      assert canceled_event.signal.id in trace_ids
      assert cause_signal.id in trace_ids

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
               ) + 1

      assert snapshot.retry_by_category == baseline.retry_by_category
    end)
  end

  test "ok cancel with invalid cause_id falls back to uncoupled tracing across backends" do
    Enum.each([:jido_ai, :harness], fn backend ->
      :ok = Telemetry.reset()
      baseline = Telemetry.snapshot().llm

      put_runtime_backend!(backend,
        include_execution_ref?: true,
        cancel_scenario: :ok,
        test_pid: self()
      )

      conversation_id = unique_id("cancel-ok-invalid-cause-conversation-#{backend}")
      effect_id = unique_id("cancel-ok-invalid-cause-effect-#{backend}")
      invalid_cause_id = unique_id("cancel-ok-invalid-cause-#{backend}")
      replay_start = DateTime.utc_now() |> DateTime.to_unix()

      :ok =
        EffectManager.start_effect(
          %{
            effect_id: effect_id,
            conversation_id: conversation_id,
            class: :llm,
            kind: "generation",
            input: %{content: "cancel me with invalid cause"},
            policy: %{max_attempts: 1, backoff_ms: 5, timeout_ms: 1_000}
          },
          nil
        )

      assert_receive {:cancel_matrix_stream_started, ^backend, execution_ref}, @assert_timeout
      assert is_pid(execution_ref)
      Process.sleep(50)

      :ok = EffectManager.cancel_conversation(conversation_id, "user_abort", invalid_cause_id)
      assert_receive {:cancel_matrix_cancel_called, :ok, ^execution_ref}, @assert_timeout

      canceled_event =
        eventually(fn ->
          case Ingest.replay("conv.effect.llm.generation.canceled", replay_start) do
            {:ok, records} ->
              records
              |> Enum.find(fn record ->
                effect_id_for(record) == effect_id and lifecycle_for(record) == "canceled"
              end)
              |> case do
                nil -> :retry
                event -> {:ok, event}
              end

            _other ->
              :retry
          end
        end)

      assert data_field(canceled_event, :reason, nil) == "user_abort"
      assert data_field(canceled_event, :backend_cancel, nil) == "ok"
      assert data_field(canceled_event, :backend, nil) == Atom.to_string(backend)
      assert data_field(canceled_event, :model, nil) == "matrix-model"

      expected_provider =
        case backend do
          :jido_ai -> "matrix-provider"
          :harness -> "codex"
        end

      assert data_field(canceled_event, :provider, nil) == expected_provider

      trace = Ingest.trace_chain(canceled_event.signal.id, :backward)
      trace_ids = Enum.map(trace, & &1.id)

      assert canceled_event.signal.id in trace_ids
      refute invalid_cause_id in trace_ids

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
               ) + 1

      assert snapshot.retry_by_category == baseline.retry_by_category
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

      assert_receive {:cancel_matrix_stream_started, ^backend, nil}, @assert_timeout

      :ok = EffectManager.cancel_conversation(conversation_id, "user_abort", nil)
      refute_receive {:cancel_matrix_cancel_called, _, _}, 200

      canceled_event =
        eventually(fn ->
          case Ingest.replay("conv.effect.llm.generation.canceled", replay_start) do
            {:ok, records} ->
              records
              |> Enum.find(fn record ->
                effect_id_for(record) == effect_id and lifecycle_for(record) == "canceled"
              end)
              |> case do
                nil -> :retry
                event -> {:ok, event}
              end

            _other ->
              :retry
          end
        end)

      assert data_field(canceled_event, :reason, nil) == "user_abort"
      assert data_field(canceled_event, :backend_cancel, nil) == "not_available"
      assert data_field(canceled_event, :backend, nil) == Atom.to_string(backend)
      assert data_field(canceled_event, :model, nil) == "matrix-model"

      expected_provider =
        case backend do
          :jido_ai -> "matrix-provider"
          :harness -> "codex"
        end

      assert data_field(canceled_event, :provider, nil) == expected_provider
      assert_terminal_canceled_only!(effect_id, replay_start)

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

      assert backend_lifecycle_count(
               snapshot.lifecycle_by_backend,
               Atom.to_string(backend),
               :canceled
             ) >=
               backend_lifecycle_count(
                 baseline.lifecycle_by_backend,
                 Atom.to_string(backend),
                 :canceled
               ) + 1

      assert snapshot.retry_by_category == baseline.retry_by_category
    end)
  end

  test "not_available cancel with explicit cause_id links canceled lifecycle across backends" do
    Enum.each([:jido_ai, :harness], fn backend ->
      :ok = Telemetry.reset()
      baseline = Telemetry.snapshot().llm

      put_runtime_backend!(backend,
        include_execution_ref?: false,
        cancel_scenario: :ok,
        test_pid: self()
      )

      conversation_id = unique_id("cancel-na-cause-link-conversation-#{backend}")
      effect_id = unique_id("cancel-na-cause-link-effect-#{backend}")
      replay_start = DateTime.utc_now() |> DateTime.to_unix()

      assert {:ok, %{signal: cause_signal}} =
               Ingest.ingest(%{
                 id: unique_id("cancel-na-cause-link-cause-#{backend}"),
                 type: "conv.audit.policy.decision_recorded",
                 source: "/tests/llm-cancel-telemetry-matrix",
                 subject: conversation_id,
                 data: %{
                   audit_id: unique_id("cancel-na-cause-link-audit-#{backend}"),
                   category: "policy",
                   decision: "allow"
                 },
                 extensions: %{contract_major: 1}
               })

      :ok =
        EffectManager.start_effect(
          %{
            effect_id: effect_id,
            conversation_id: conversation_id,
            class: :llm,
            kind: "generation",
            input: %{content: "cancel me without execution ref and explicit cause"},
            policy: %{max_attempts: 1, backoff_ms: 5, timeout_ms: 1_000}
          },
          nil
        )

      assert_receive {:cancel_matrix_stream_started, ^backend, nil}, @assert_timeout

      :ok = EffectManager.cancel_conversation(conversation_id, "user_abort", cause_signal.id)
      refute_receive {:cancel_matrix_cancel_called, _, _}, 200

      canceled_event =
        eventually(fn ->
          case Ingest.replay("conv.effect.llm.generation.canceled", replay_start) do
            {:ok, records} ->
              records
              |> Enum.find(fn record ->
                effect_id_for(record) == effect_id and lifecycle_for(record) == "canceled"
              end)
              |> case do
                nil -> :retry
                event -> {:ok, event}
              end

            _other ->
              :retry
          end
        end)

      assert data_field(canceled_event, :reason, nil) == "user_abort"
      assert data_field(canceled_event, :backend_cancel, nil) == "not_available"
      assert data_field(canceled_event, :backend, nil) == Atom.to_string(backend)
      assert data_field(canceled_event, :model, nil) == "matrix-model"

      expected_provider =
        case backend do
          :jido_ai -> "matrix-provider"
          :harness -> "codex"
        end

      assert data_field(canceled_event, :provider, nil) == expected_provider

      trace = Ingest.trace_chain(canceled_event.signal.id, :backward)
      trace_ids = Enum.map(trace, & &1.id)

      assert canceled_event.signal.id in trace_ids
      assert cause_signal.id in trace_ids

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

      assert backend_lifecycle_count(
               snapshot.lifecycle_by_backend,
               Atom.to_string(backend),
               :canceled
             ) >=
               backend_lifecycle_count(
                 baseline.lifecycle_by_backend,
                 Atom.to_string(backend),
                 :canceled
               ) + 1

      assert snapshot.retry_by_category == baseline.retry_by_category
    end)
  end

  test "not_available cancel with invalid cause_id falls back to uncoupled tracing across backends" do
    Enum.each([:jido_ai, :harness], fn backend ->
      :ok = Telemetry.reset()
      baseline = Telemetry.snapshot().llm

      put_runtime_backend!(backend,
        include_execution_ref?: false,
        cancel_scenario: :ok,
        test_pid: self()
      )

      conversation_id = unique_id("cancel-na-invalid-cause-conversation-#{backend}")
      effect_id = unique_id("cancel-na-invalid-cause-effect-#{backend}")
      invalid_cause_id = unique_id("cancel-na-invalid-cause-#{backend}")
      replay_start = DateTime.utc_now() |> DateTime.to_unix()

      :ok =
        EffectManager.start_effect(
          %{
            effect_id: effect_id,
            conversation_id: conversation_id,
            class: :llm,
            kind: "generation",
            input: %{content: "cancel me without execution ref and invalid cause"},
            policy: %{max_attempts: 1, backoff_ms: 5, timeout_ms: 1_000}
          },
          nil
        )

      assert_receive {:cancel_matrix_stream_started, ^backend, nil}, @assert_timeout

      :ok = EffectManager.cancel_conversation(conversation_id, "user_abort", invalid_cause_id)
      refute_receive {:cancel_matrix_cancel_called, _, _}, 200

      canceled_event =
        eventually(fn ->
          case Ingest.replay("conv.effect.llm.generation.canceled", replay_start) do
            {:ok, records} ->
              records
              |> Enum.find(fn record ->
                effect_id_for(record) == effect_id and lifecycle_for(record) == "canceled"
              end)
              |> case do
                nil -> :retry
                event -> {:ok, event}
              end

            _other ->
              :retry
          end
        end)

      assert data_field(canceled_event, :reason, nil) == "user_abort"
      assert data_field(canceled_event, :backend_cancel, nil) == "not_available"
      assert data_field(canceled_event, :backend, nil) == Atom.to_string(backend)
      assert data_field(canceled_event, :model, nil) == "matrix-model"

      expected_provider =
        case backend do
          :jido_ai -> "matrix-provider"
          :harness -> "codex"
        end

      assert data_field(canceled_event, :provider, nil) == expected_provider

      trace = Ingest.trace_chain(canceled_event.signal.id, :backward)
      trace_ids = Enum.map(trace, & &1.id)

      assert canceled_event.signal.id in trace_ids
      refute invalid_cause_id in trace_ids

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

      assert backend_lifecycle_count(
               snapshot.lifecycle_by_backend,
               Atom.to_string(backend),
               :canceled
             ) >=
               backend_lifecycle_count(
                 baseline.lifecycle_by_backend,
                 Atom.to_string(backend),
                 :canceled
               ) + 1

      assert snapshot.retry_by_category == baseline.retry_by_category
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

      assert_receive {:cancel_matrix_stream_started, ^backend, execution_ref}, @assert_timeout
      assert is_pid(execution_ref)
      Process.sleep(50)

      :ok = EffectManager.cancel_conversation(conversation_id, "user_abort", nil)
      assert_receive {:cancel_matrix_cancel_called, :failed, ^execution_ref}, @assert_timeout

      canceled_event =
        eventually(fn ->
          case Ingest.replay("conv.effect.llm.generation.canceled", replay_start) do
            {:ok, records} ->
              records
              |> Enum.find(fn record ->
                effect_id_for(record) == effect_id and lifecycle_for(record) == "canceled"
              end)
              |> case do
                nil -> :retry
                event -> {:ok, event}
              end

            _other ->
              :retry
          end
        end)

      assert data_field(canceled_event, :reason, nil) == "user_abort"
      assert data_field(canceled_event, :backend_cancel, nil) == "failed"
      assert data_field(canceled_event, :backend_cancel_reason, nil) == "cancel failed"
      assert data_field(canceled_event, :backend_cancel_category, nil) == "provider"
      assert data_field(canceled_event, :backend_cancel_retryable?, nil) == true
      assert data_field(canceled_event, :backend, nil) == Atom.to_string(backend)
      assert data_field(canceled_event, :model, nil) == "matrix-model"

      expected_provider =
        case backend do
          :jido_ai -> "matrix-provider"
          :harness -> "codex"
        end

      assert data_field(canceled_event, :provider, nil) == expected_provider
      assert_terminal_canceled_only!(effect_id, replay_start)

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

      assert backend_lifecycle_count(
               snapshot.lifecycle_by_backend,
               Atom.to_string(backend),
               :canceled
             ) >=
               backend_lifecycle_count(
                 baseline.lifecycle_by_backend,
                 Atom.to_string(backend),
                 :canceled
               ) + 1

      assert snapshot.retry_by_category == baseline.retry_by_category
    end)
  end

  test "failed cancel with explicit cause_id links canceled lifecycle across backends" do
    Enum.each([:jido_ai, :harness], fn backend ->
      :ok = Telemetry.reset()
      baseline = Telemetry.snapshot().llm

      put_runtime_backend!(backend,
        include_execution_ref?: true,
        cancel_scenario: :failed,
        test_pid: self()
      )

      conversation_id = unique_id("cancel-failed-cause-link-conversation-#{backend}")
      effect_id = unique_id("cancel-failed-cause-link-effect-#{backend}")
      replay_start = DateTime.utc_now() |> DateTime.to_unix()

      assert {:ok, %{signal: cause_signal}} =
               Ingest.ingest(%{
                 id: unique_id("cancel-failed-cause-link-cause-#{backend}"),
                 type: "conv.audit.policy.decision_recorded",
                 source: "/tests/llm-cancel-telemetry-matrix",
                 subject: conversation_id,
                 data: %{
                   audit_id: unique_id("cancel-failed-cause-link-audit-#{backend}"),
                   category: "policy",
                   decision: "allow"
                 },
                 extensions: %{contract_major: 1}
               })

      :ok =
        EffectManager.start_effect(
          %{
            effect_id: effect_id,
            conversation_id: conversation_id,
            class: :llm,
            kind: "generation",
            input: %{content: "cancel me with backend failure and explicit cause"},
            policy: %{max_attempts: 1, backoff_ms: 5, timeout_ms: 1_000}
          },
          nil
        )

      assert_receive {:cancel_matrix_stream_started, ^backend, execution_ref}, @assert_timeout
      assert is_pid(execution_ref)
      Process.sleep(50)

      :ok = EffectManager.cancel_conversation(conversation_id, "user_abort", cause_signal.id)
      assert_receive {:cancel_matrix_cancel_called, :failed, ^execution_ref}, @assert_timeout

      canceled_event =
        eventually(fn ->
          case Ingest.replay("conv.effect.llm.generation.canceled", replay_start) do
            {:ok, records} ->
              records
              |> Enum.find(fn record ->
                effect_id_for(record) == effect_id and lifecycle_for(record) == "canceled"
              end)
              |> case do
                nil -> :retry
                event -> {:ok, event}
              end

            _other ->
              :retry
          end
        end)

      assert data_field(canceled_event, :reason, nil) == "user_abort"
      assert data_field(canceled_event, :backend_cancel, nil) == "failed"
      assert data_field(canceled_event, :backend_cancel_reason, nil) == "cancel failed"
      assert data_field(canceled_event, :backend_cancel_category, nil) == "provider"
      assert data_field(canceled_event, :backend_cancel_retryable?, nil) == true
      assert data_field(canceled_event, :backend, nil) == Atom.to_string(backend)
      assert data_field(canceled_event, :model, nil) == "matrix-model"

      expected_provider =
        case backend do
          :jido_ai -> "matrix-provider"
          :harness -> "codex"
        end

      assert data_field(canceled_event, :provider, nil) == expected_provider

      trace = Ingest.trace_chain(canceled_event.signal.id, :backward)
      trace_ids = Enum.map(trace, & &1.id)

      assert canceled_event.signal.id in trace_ids
      assert cause_signal.id in trace_ids

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

      assert backend_lifecycle_count(
               snapshot.lifecycle_by_backend,
               Atom.to_string(backend),
               :canceled
             ) >=
               backend_lifecycle_count(
                 baseline.lifecycle_by_backend,
                 Atom.to_string(backend),
                 :canceled
               ) + 1

      assert snapshot.retry_by_category == baseline.retry_by_category
    end)
  end

  test "failed cancel with invalid cause_id falls back to uncoupled tracing across backends" do
    Enum.each([:jido_ai, :harness], fn backend ->
      :ok = Telemetry.reset()
      baseline = Telemetry.snapshot().llm

      put_runtime_backend!(backend,
        include_execution_ref?: true,
        cancel_scenario: :failed,
        test_pid: self()
      )

      conversation_id = unique_id("cancel-failed-invalid-cause-conversation-#{backend}")
      effect_id = unique_id("cancel-failed-invalid-cause-effect-#{backend}")
      invalid_cause_id = unique_id("cancel-failed-invalid-cause-#{backend}")
      replay_start = DateTime.utc_now() |> DateTime.to_unix()

      :ok =
        EffectManager.start_effect(
          %{
            effect_id: effect_id,
            conversation_id: conversation_id,
            class: :llm,
            kind: "generation",
            input: %{content: "cancel me with backend failure and invalid cause"},
            policy: %{max_attempts: 1, backoff_ms: 5, timeout_ms: 1_000}
          },
          nil
        )

      assert_receive {:cancel_matrix_stream_started, ^backend, execution_ref}, @assert_timeout
      assert is_pid(execution_ref)
      Process.sleep(50)

      :ok = EffectManager.cancel_conversation(conversation_id, "user_abort", invalid_cause_id)
      assert_receive {:cancel_matrix_cancel_called, :failed, ^execution_ref}, @assert_timeout

      canceled_event =
        eventually(fn ->
          case Ingest.replay("conv.effect.llm.generation.canceled", replay_start) do
            {:ok, records} ->
              records
              |> Enum.find(fn record ->
                effect_id_for(record) == effect_id and lifecycle_for(record) == "canceled"
              end)
              |> case do
                nil -> :retry
                event -> {:ok, event}
              end

            _other ->
              :retry
          end
        end)

      assert data_field(canceled_event, :reason, nil) == "user_abort"
      assert data_field(canceled_event, :backend_cancel, nil) == "failed"
      assert data_field(canceled_event, :backend_cancel_reason, nil) == "cancel failed"
      assert data_field(canceled_event, :backend_cancel_category, nil) == "provider"
      assert data_field(canceled_event, :backend_cancel_retryable?, nil) == true
      assert data_field(canceled_event, :backend, nil) == Atom.to_string(backend)
      assert data_field(canceled_event, :model, nil) == "matrix-model"

      expected_provider =
        case backend do
          :jido_ai -> "matrix-provider"
          :harness -> "codex"
        end

      assert data_field(canceled_event, :provider, nil) == expected_provider

      trace = Ingest.trace_chain(canceled_event.signal.id, :backward)
      trace_ids = Enum.map(trace, & &1.id)

      assert canceled_event.signal.id in trace_ids
      refute invalid_cause_id in trace_ids

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

      assert backend_lifecycle_count(
               snapshot.lifecycle_by_backend,
               Atom.to_string(backend),
               :canceled
             ) >=
               backend_lifecycle_count(
                 baseline.lifecycle_by_backend,
                 Atom.to_string(backend),
                 :canceled
               ) + 1

      assert snapshot.retry_by_category == baseline.retry_by_category
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

  defp assert_terminal_canceled_only!(effect_id, replay_start) do
    terminal_events =
      eventually(fn ->
        case Ingest.replay("conv.effect.llm.generation.**", replay_start) do
          {:ok, records} ->
            events_for_effect = Enum.filter(records, &(effect_id_for(&1) == effect_id))

            terminal_events =
              Enum.filter(events_for_effect, fn event ->
                lifecycle_for(event) in ["completed", "failed", "canceled"]
              end)

            if Enum.any?(terminal_events, &(lifecycle_for(&1) == "canceled")) do
              {:ok, terminal_events}
            else
              :retry
            end

          _other ->
            :retry
        end
      end)

    assert Enum.count(terminal_events, &(lifecycle_for(&1) == "canceled")) == 1
    refute Enum.any?(terminal_events, &(lifecycle_for(&1) == "completed"))
    refute Enum.any?(terminal_events, &(lifecycle_for(&1) == "failed"))
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
