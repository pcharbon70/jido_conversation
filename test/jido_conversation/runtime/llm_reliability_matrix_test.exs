defmodule Jido.Conversation.Runtime.LLMReliabilityMatrixTest do
  use ExUnit.Case, async: false

  alias Jido.Conversation.Ingest
  alias Jido.Conversation.LLM.Request
  alias Jido.Conversation.Projections
  alias Jido.Conversation.Projections.LlmContext
  alias Jido.Conversation.Projections.Timeline
  alias Jido.Conversation.Runtime.Coordinator
  alias Jido.Conversation.Runtime.EffectManager
  alias Jido.Conversation.Runtime.IngressSubscriber

  @app :jido_conversation
  @key Jido.Conversation.EventSystem

  defmodule JidoAIMatrixBackendStub do
    @behaviour Jido.Conversation.LLM.Backend

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
    def start(%Request{} = request, opts) do
      send(Keyword.get(opts, :test_pid, self()), {:matrix_start, :jido_ai, request})

      {:ok,
       Result.new!(%{
         request_id: request.request_id,
         conversation_id: request.conversation_id,
         backend: request.backend,
         status: :completed,
         text: "matrix jido_ai start",
         provider: request.provider || "anthropic",
         model: request.model || "anthropic:claude-sonnet",
         usage: %{input_tokens: 2, output_tokens: 3}
       })}
    end

    @impl true
    def stream(%Request{} = request, emit, opts) do
      test_pid = Keyword.get(opts, :test_pid, self())
      execution_ref = self()

      send(test_pid, {:matrix_stream_started, :jido_ai, request, execution_ref})

      _ =
        emit.(
          Event.new!(%{
            request_id: request.request_id,
            conversation_id: request.conversation_id,
            backend: request.backend,
            lifecycle: :started,
            provider: request.provider || "anthropic",
            model: request.model || "anthropic:claude-sonnet",
            metadata: %{execution_ref: execution_ref}
          })
        )

      _ =
        emit.(
          Event.new!(%{
            request_id: request.request_id,
            conversation_id: request.conversation_id,
            backend: request.backend,
            lifecycle: :delta,
            delta: "alpha ",
            provider: request.provider || "anthropic",
            model: request.model || "anthropic:claude-sonnet"
          })
        )

      _ =
        emit.(
          Event.new!(%{
            request_id: request.request_id,
            conversation_id: request.conversation_id,
            backend: request.backend,
            lifecycle: :delta,
            delta: "beta",
            provider: request.provider || "anthropic",
            model: request.model || "anthropic:claude-sonnet"
          })
        )

      {:ok,
       Result.new!(%{
         request_id: request.request_id,
         conversation_id: request.conversation_id,
         backend: request.backend,
         status: :completed,
         text: "alpha beta",
         provider: request.provider || "anthropic",
         model: request.model || "anthropic:claude-sonnet",
         usage: %{input_tokens: 4, output_tokens: 2}
       })}
    end

    @impl true
    def cancel(execution_ref, opts) do
      send(Keyword.get(opts, :test_pid, self()), {:matrix_cancel, :jido_ai, execution_ref})
      send(execution_ref, :cancel)
      :ok
    end
  end

  defmodule HarnessMatrixBackendStub do
    @behaviour Jido.Conversation.LLM.Backend

    alias Jido.Conversation.LLM.Event
    alias Jido.Conversation.LLM.Request
    alias Jido.Conversation.LLM.Result

    @impl true
    def capabilities do
      %{
        streaming?: true,
        cancellation?: true,
        provider_selection?: false,
        model_selection?: false
      }
    end

    @impl true
    def start(%Request{} = request, opts) do
      send(Keyword.get(opts, :test_pid, self()), {:matrix_start, :harness, request})

      {:ok,
       Result.new!(%{
         request_id: request.request_id,
         conversation_id: request.conversation_id,
         backend: request.backend,
         status: :completed,
         text: "matrix harness start",
         provider: :codex,
         model: "harness-default",
         usage: %{input_tokens: 1, output_tokens: 1}
       })}
    end

    @impl true
    def stream(%Request{} = request, emit, opts) do
      test_pid = Keyword.get(opts, :test_pid, self())
      execution_ref = %{provider: :codex, session_id: "session-matrix-1"}

      send(test_pid, {:matrix_stream_started, :harness, request, execution_ref})

      _ =
        emit.(
          Event.new!(%{
            request_id: request.request_id,
            conversation_id: request.conversation_id,
            backend: request.backend,
            lifecycle: :started,
            provider: :codex,
            model: "harness-default",
            metadata: %{execution_ref: execution_ref}
          })
        )

      _ =
        emit.(
          Event.new!(%{
            request_id: request.request_id,
            conversation_id: request.conversation_id,
            backend: request.backend,
            lifecycle: :thinking,
            content: "planning",
            provider: :codex,
            model: "harness-default"
          })
        )

      _ =
        emit.(
          Event.new!(%{
            request_id: request.request_id,
            conversation_id: request.conversation_id,
            backend: request.backend,
            lifecycle: :delta,
            delta: "gamma ",
            provider: :codex,
            model: "harness-default"
          })
        )

      _ =
        emit.(
          Event.new!(%{
            request_id: request.request_id,
            conversation_id: request.conversation_id,
            backend: request.backend,
            lifecycle: :delta,
            delta: "delta",
            provider: :codex,
            model: "harness-default"
          })
        )

      {:ok,
       Result.new!(%{
         request_id: request.request_id,
         conversation_id: request.conversation_id,
         backend: request.backend,
         status: :completed,
         text: "gamma delta",
         provider: :codex,
         model: "harness-default",
         usage: %{input_tokens: 5, output_tokens: 4},
         metadata: %{session_id: "session-matrix-1"}
       })}
    end

    @impl true
    def cancel(execution_ref, opts) do
      send(Keyword.get(opts, :test_pid, self()), {:matrix_cancel, :harness, execution_ref})
      :ok
    end
  end

  defmodule TimeoutCancelRaceBackendStub do
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
    def start(%Request{} = request, opts) do
      send(Keyword.get(opts, :test_pid, self()), {:race_start, request})

      {:ok,
       Result.new!(%{
         request_id: request.request_id,
         conversation_id: request.conversation_id,
         backend: request.backend,
         status: :completed,
         text: "race start completed",
         provider: request.provider || "race-provider",
         model: request.model || "race-model"
       })}
    end

    @impl true
    def stream(%Request{} = request, emit, opts) do
      test_pid = Keyword.get(opts, :test_pid, self())
      execution_ref = self()
      sleep_ms = Keyword.get(opts, :sleep_ms, 240)

      send(test_pid, {:race_stream_started, request, execution_ref})

      _ =
        emit.(
          Event.new!(%{
            request_id: request.request_id,
            conversation_id: request.conversation_id,
            backend: request.backend,
            lifecycle: :started,
            provider: request.provider || "race-provider",
            model: request.model || "race-model",
            metadata: %{execution_ref: execution_ref}
          })
        )

      receive do
        :cancel ->
          send(test_pid, {:race_stream_canceled, execution_ref})
          {:error, Error.new!(category: :canceled, message: "race canceled", retryable?: false)}
      after
        sleep_ms ->
          send(test_pid, {:race_stream_timeout_path, execution_ref})

          {:ok,
           Result.new!(%{
             request_id: request.request_id,
             conversation_id: request.conversation_id,
             backend: request.backend,
             status: :completed,
             text: "late completion"
           })}
      end
    end

    @impl true
    def cancel(execution_ref, opts) do
      send(Keyword.get(opts, :test_pid, self()), {:race_cancel_called, execution_ref})
      send(execution_ref, :cancel)
      :ok
    end
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

  test "backend matrix runtime path preserves lifecycle/output contracts for jido_ai and harness backends" do
    matrix_cases = [
      %{
        name: :jido_ai,
        backend: :jido_ai,
        module: JidoAIMatrixBackendStub,
        expected_provider: "anthropic",
        expected_model: "anthropic:claude-sonnet",
        expected_text: "alpha beta"
      },
      %{
        name: :harness,
        backend: :harness,
        module: HarnessMatrixBackendStub,
        expected_provider: "codex",
        expected_model: "harness-default",
        expected_text: "gamma delta"
      }
    ]

    Enum.each(matrix_cases, fn matrix_case ->
      put_runtime_llm_backend!(matrix_case.module, matrix_case.backend, self())

      conversation_id = unique_id("conversation-#{matrix_case.name}")
      effect_id = unique_id("effect-#{matrix_case.name}")
      replay_start = DateTime.utc_now() |> DateTime.to_unix()

      :ok =
        EffectManager.start_effect(
          %{
            effect_id: effect_id,
            conversation_id: conversation_id,
            class: :llm,
            kind: "generation",
            input: %{content: "matrix #{matrix_case.name}"},
            policy: %{max_attempts: 1, backoff_ms: 5, timeout_ms: 1_000}
          },
          nil
        )

      assert_receive {:matrix_stream_started, backend_name, %Request{}, _execution_ref}
      assert backend_name == matrix_case.name

      effect_events =
        eventually(fn ->
          case Ingest.replay("conv.effect.llm.generation.**", replay_start) do
            {:ok, records} ->
              matches = Enum.filter(records, &(effect_id_for(&1) == effect_id))
              lifecycles = Enum.map(matches, &lifecycle_for/1) |> MapSet.new()

              if MapSet.subset?(MapSet.new(["started", "progress", "completed"]), lifecycles) do
                {:ok, matches}
              else
                :retry
              end

            _other ->
              :retry
          end
        end)

      assert Enum.any?(effect_events, fn event ->
               lifecycle_for(event) == "completed" and
                 get_in(data_field(event, :result, %{}), [:text]) == matrix_case.expected_text and
                 get_in(data_field(event, :result, %{}), [:provider]) ==
                   matrix_case.expected_provider and
                 get_in(data_field(event, :result, %{}), [:model]) == matrix_case.expected_model
             end)

      output_events =
        eventually(fn ->
          case Ingest.replay("conv.out.assistant.**", replay_start) do
            {:ok, records} ->
              matches = Enum.filter(records, &(data_field(&1, :effect_id, nil) == effect_id))
              out_types = Enum.map(matches, & &1.signal.type)

              if "conv.out.assistant.delta" in out_types and
                   "conv.out.assistant.completed" in out_types do
                {:ok, matches}
              else
                :retry
              end

            _other ->
              :retry
          end
        end)

      assert Enum.any?(output_events, &(&1.signal.type == "conv.out.assistant.delta"))

      assert Enum.any?(output_events, fn event ->
               event.signal.type == "conv.out.assistant.completed" and
                 data_field(event, :content, nil) == matrix_case.expected_text
             end)
    end)
  end

  test "timeout/cancel race produces a single terminal lifecycle and never emits completed" do
    put_runtime_llm_backend!(
      TimeoutCancelRaceBackendStub,
      :jido_ai,
      self(),
      timeout_ms: 80,
      backend_opts: [sleep_ms: 220]
    )

    conversation_id = unique_id("conversation-race")
    effect_id = unique_id("effect-race")
    replay_start = DateTime.utc_now() |> DateTime.to_unix()

    :ok =
      EffectManager.start_effect(
        %{
          effect_id: effect_id,
          conversation_id: conversation_id,
          class: :llm,
          kind: "generation",
          input: %{content: "race condition test"},
          policy: %{max_attempts: 1, backoff_ms: 5, timeout_ms: 80}
        },
        nil
      )

    assert_receive {:race_stream_started, %Request{}, execution_ref}
    Process.sleep(60)
    :ok = EffectManager.cancel_conversation(conversation_id, "user_abort", nil)

    _ =
      receive do
        {:race_cancel_called, ^execution_ref} -> :ok
      after
        200 -> :ok
      end

    effect_events =
      eventually(fn ->
        case Ingest.replay("conv.effect.llm.generation.**", replay_start) do
          {:ok, records} ->
            matches = Enum.filter(records, &(effect_id_for(&1) == effect_id))
            lifecycles = Enum.map(matches, &lifecycle_for/1)

            if Enum.any?(lifecycles, &(&1 in ["failed", "canceled"])) do
              {:ok, matches}
            else
              :retry
            end

          _other ->
            :retry
        end
      end)

    terminal_lifecycles =
      effect_events
      |> Enum.map(&lifecycle_for/1)
      |> Enum.filter(&(&1 in ["completed", "failed", "canceled"]))

    assert Enum.count(terminal_lifecycles, &(&1 in ["failed", "canceled"])) == 1
    refute "completed" in terminal_lifecycles
  end

  test "replay parity stays stable for sampled traces generated through both backend paths" do
    scenarios = [
      %{name: :jido_ai, backend: :jido_ai, module: JidoAIMatrixBackendStub},
      %{name: :harness, backend: :harness, module: HarnessMatrixBackendStub}
    ]

    Enum.each(scenarios, fn scenario ->
      put_runtime_llm_backend!(scenario.module, scenario.backend, self())

      conversation_id = unique_id("conversation-parity-#{scenario.name}")
      effect_id = unique_id("effect-parity-#{scenario.name}")

      :ok =
        EffectManager.start_effect(
          %{
            effect_id: effect_id,
            conversation_id: conversation_id,
            class: :llm,
            kind: "generation",
            input: %{content: "replay parity #{scenario.name}"},
            policy: %{max_attempts: 1, backoff_ms: 5, timeout_ms: 1_000}
          },
          nil
        )

      assert_receive {:matrix_stream_started, backend_name, %Request{}, _execution_ref}
      assert backend_name == scenario.name

      eventually(fn ->
        signals = Ingest.conversation_events(conversation_id)

        if Enum.any?(signals, fn signal ->
             signal.type == "conv.out.assistant.completed" and
               (Map.get(signal.data, :effect_id) || Map.get(signal.data, "effect_id")) ==
                 effect_id
           end) do
          {:ok, :completed}
        else
          :retry
        end
      end)

      wait_for_runtime_idle!()

      live_timeline = Projections.timeline(conversation_id, coalesce_deltas: false)

      live_context =
        Projections.llm_context(conversation_id, include_deltas: true, max_messages: 200)

      replayed_signals =
        eventually(fn ->
          signals = Ingest.conversation_events(conversation_id)

          if Enum.any?(signals, &(&1.type == "conv.out.assistant.completed")) do
            {:ok, signals}
          else
            :retry
          end
        end)

      replay_timeline = Timeline.from_events(replayed_signals, coalesce_deltas: false)

      replay_context =
        LlmContext.from_events(replayed_signals, include_deltas: true, max_messages: 200)

      assert live_timeline == replay_timeline
      assert live_context == replay_context
    end)
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

  defp lifecycle_for(record) do
    data_field(record, :lifecycle, "")
  end

  defp effect_id_for(record) do
    data_field(record, :effect_id, nil)
  end

  defp data_field(record, key, default) do
    data = record.signal.data || %{}

    case Map.fetch(data, key) do
      {:ok, value} ->
        value

      :error ->
        Map.get(data, to_string(key), default)
    end
  end

  defp put_runtime_llm_backend!(module, backend, test_pid, opts \\ [])
       when is_atom(module) and backend in [:jido_ai, :harness] and is_pid(test_pid) do
    timeout_ms = Keyword.get(opts, :timeout_ms, 1_000)
    backend_opts = [test_pid: test_pid] ++ Keyword.get(opts, :backend_opts, [])

    jido_ai_cfg =
      if backend == :jido_ai do
        [
          module: module,
          stream?: true,
          timeout_ms: timeout_ms,
          provider: "anthropic",
          model: "anthropic:claude-sonnet",
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
          module: module,
          stream?: true,
          timeout_ms: timeout_ms,
          provider: "codex",
          model: "harness-default",
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
