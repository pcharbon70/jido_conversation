defmodule JidoConversation.Runtime.EffectManagerTest do
  use ExUnit.Case, async: false

  alias JidoConversation.Ingest
  alias JidoConversation.LLM.Event
  alias JidoConversation.LLM.Request
  alias JidoConversation.LLM.Result
  alias JidoConversation.Runtime.Coordinator
  alias JidoConversation.Runtime.EffectManager
  alias JidoConversation.Runtime.IngressSubscriber
  alias JidoConversation.Telemetry

  @app :jido_conversation
  @key JidoConversation.EventSystem

  defmodule LLMBackendStub do
    @behaviour JidoConversation.LLM.Backend

    alias JidoConversation.LLM.Event
    alias JidoConversation.LLM.Request
    alias JidoConversation.LLM.Result

    @impl true
    def capabilities do
      %{
        streaming?: true,
        cancellation?: false,
        provider_selection?: true,
        model_selection?: true
      }
    end

    @impl true
    def start(%Request{} = request, opts) do
      send(Keyword.get(opts, :test_pid, self()), {:llm_backend_start, request, opts})

      {:ok,
       Result.new!(%{
         request_id: request.request_id,
         conversation_id: request.conversation_id,
         backend: request.backend,
         status: :completed,
         text: "hello world",
         provider: request.provider || "stub-provider",
         model: request.model || "stub-model",
         usage: %{input_tokens: 3, output_tokens: 2}
       })}
    end

    @impl true
    def stream(%Request{} = request, emit, opts) when is_function(emit, 1) do
      send(Keyword.get(opts, :test_pid, self()), {:llm_backend_stream, request, opts})

      _ =
        emit.(
          Event.new!(%{
            request_id: request.request_id,
            conversation_id: request.conversation_id,
            backend: request.backend,
            lifecycle: :started,
            provider: request.provider || "stub-provider",
            model: request.model || "stub-model"
          })
        )

      _ =
        emit.(
          Event.new!(%{
            request_id: request.request_id,
            conversation_id: request.conversation_id,
            backend: request.backend,
            lifecycle: :delta,
            delta: "hello ",
            provider: request.provider || "stub-provider",
            model: request.model || "stub-model"
          })
        )

      _ =
        emit.(
          Event.new!(%{
            request_id: request.request_id,
            conversation_id: request.conversation_id,
            backend: request.backend,
            lifecycle: :delta,
            delta: "world",
            provider: request.provider || "stub-provider",
            model: request.model || "stub-model"
          })
        )

      {:ok,
       Result.new!(%{
         request_id: request.request_id,
         conversation_id: request.conversation_id,
         backend: request.backend,
         status: :completed,
         text: "hello world",
         provider: request.provider || "stub-provider",
         model: request.model || "stub-model",
         usage: %{input_tokens: 3, output_tokens: 2}
       })}
    end

    @impl true
    def cancel(_execution_ref, _opts), do: :ok
  end

  defmodule LLMNonRetryableBackendStub do
    @behaviour JidoConversation.LLM.Backend

    alias JidoConversation.LLM.Error
    alias JidoConversation.LLM.Request

    @impl true
    def capabilities do
      %{
        streaming?: true,
        cancellation?: false,
        provider_selection?: true,
        model_selection?: true
      }
    end

    @impl true
    def start(%Request{} = request, opts) do
      send(Keyword.get(opts, :test_pid, self()), {:llm_non_retryable_start, request})

      {:error,
       Error.new!(category: :config, message: "non-retryable config error", retryable?: false)}
    end

    @impl true
    def stream(%Request{} = request, _emit, opts) do
      send(Keyword.get(opts, :test_pid, self()), {:llm_non_retryable_stream, request})

      {:error,
       Error.new!(category: :config, message: "non-retryable config error", retryable?: false)}
    end

    @impl true
    def cancel(_execution_ref, _opts), do: :ok
  end

  defmodule LLMRetryableProviderBackendStub do
    @behaviour JidoConversation.LLM.Backend

    alias JidoConversation.LLM.Error
    alias JidoConversation.LLM.Event
    alias JidoConversation.LLM.Request
    alias JidoConversation.LLM.Result

    @impl true
    def capabilities do
      %{
        streaming?: true,
        cancellation?: false,
        provider_selection?: true,
        model_selection?: true
      }
    end

    @impl true
    def start(%Request{} = request, opts) do
      attempt = attempt_for_request(request)
      send(Keyword.get(opts, :test_pid, self()), {:llm_retryable_start, request, attempt})

      case attempt do
        1 ->
          {:error,
           Error.new!(category: :provider, message: "retryable provider error", retryable?: true)}

        _ ->
          {:ok,
           Result.new!(%{
             request_id: request.request_id,
             conversation_id: request.conversation_id,
             backend: request.backend,
             status: :completed,
             text: "recovered response",
             provider: request.provider || "stub-provider",
             model: request.model || "stub-model"
           })}
      end
    end

    @impl true
    def stream(%Request{} = request, emit, opts) when is_function(emit, 1) do
      attempt = attempt_for_request(request)
      send(Keyword.get(opts, :test_pid, self()), {:llm_retryable_stream, request, attempt})

      case attempt do
        1 ->
          {:error,
           Error.new!(category: :provider, message: "retryable provider error", retryable?: true)}

        _ ->
          _ =
            emit.(
              Event.new!(%{
                request_id: request.request_id,
                conversation_id: request.conversation_id,
                backend: request.backend,
                lifecycle: :started,
                provider: request.provider || "stub-provider",
                model: request.model || "stub-model"
              })
            )

          _ =
            emit.(
              Event.new!(%{
                request_id: request.request_id,
                conversation_id: request.conversation_id,
                backend: request.backend,
                lifecycle: :delta,
                delta: "recovered response",
                provider: request.provider || "stub-provider",
                model: request.model || "stub-model"
              })
            )

          {:ok,
           Result.new!(%{
             request_id: request.request_id,
             conversation_id: request.conversation_id,
             backend: request.backend,
             status: :completed,
             text: "recovered response",
             provider: request.provider || "stub-provider",
             model: request.model || "stub-model"
           })}
      end
    end

    @impl true
    def cancel(_execution_ref, _opts), do: :ok

    defp attempt_for_request(%Request{request_id: request_id}) when is_binary(request_id) do
      request_id
      |> String.split(":")
      |> List.last()
      |> case do
        value when is_binary(value) ->
          case Integer.parse(value) do
            {attempt, ""} -> attempt
            _ -> 1
          end

        _other ->
          1
      end
    end
  end

  defmodule LLMCancellableBackendStub do
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
    def start(%Request{} = request, opts) do
      send(Keyword.get(opts, :test_pid, self()), {:llm_cancellable_start, request})

      {:ok,
       Result.new!(%{
         request_id: request.request_id,
         conversation_id: request.conversation_id,
         backend: request.backend,
         status: :completed,
         text: "completed"
       })}
    end

    @impl true
    def stream(%Request{} = request, emit, opts) do
      test_pid = Keyword.get(opts, :test_pid, self())
      include_execution_ref? = Keyword.get(opts, :include_execution_ref?, true)
      execution_ref = if(include_execution_ref?, do: self(), else: nil)
      send(test_pid, {:llm_cancellable_stream, request, execution_ref})

      metadata =
        if is_nil(execution_ref) do
          %{}
        else
          %{execution_ref: execution_ref}
        end

      _ =
        emit.(
          Event.new!(%{
            request_id: request.request_id,
            conversation_id: request.conversation_id,
            backend: request.backend,
            lifecycle: :started,
            provider: "stub-provider",
            model: "stub-model",
            metadata: metadata
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
      send(test_pid, {:llm_cancellable_cancel_called, scenario, execution_ref})

      case scenario do
        :ok ->
          send(execution_ref, :cancel)
          :ok

        :failed ->
          {:error, Error.new!(category: :provider, message: "cancel failed", retryable?: true)}
      end
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

  test "start_effect emits started/progress/completed lifecycle and clears in-flight state" do
    conversation_id = unique_id("conversation")
    effect_id = unique_id("effect")
    replay_start = DateTime.utc_now() |> DateTime.to_unix()

    :ok =
      EffectManager.start_effect(
        %{
          effect_id: effect_id,
          conversation_id: conversation_id,
          class: :tool,
          kind: "execution",
          input: %{tool_name: "read_file"},
          simulate: %{latency_ms: 5},
          policy: %{max_attempts: 2, backoff_ms: 5, timeout_ms: 120}
        },
        nil
      )

    assert {:ok, recorded} =
             eventually(fn ->
               case Ingest.replay("conv.effect.tool.execution.**", replay_start) do
                 {:ok, events} ->
                   lifecycles = effect_lifecycles(events, effect_id)

                   if includes_all?(lifecycles, ["started", "progress", "completed"]) do
                     {:ok, {:ok, events}}
                   else
                     :retry
                   end

                 other ->
                   {:ok, other}
               end
             end)

    refute Enum.any?(recorded, fn event ->
             effect_id_for(event) == effect_id and lifecycle_for(event) == "failed"
           end)

    eventually(fn ->
      if EffectManager.stats().in_flight_count == 0 do
        {:ok, :ok}
      else
        :retry
      end
    end)
  end

  test "timeout retries and emits failed lifecycle after attempts are exhausted" do
    conversation_id = unique_id("conversation")
    effect_id = unique_id("effect")
    replay_start = DateTime.utc_now() |> DateTime.to_unix()

    :ok =
      EffectManager.start_effect(
        %{
          effect_id: effect_id,
          conversation_id: conversation_id,
          class: :tool,
          kind: "execution",
          input: %{tool_name: "slow_tool"},
          simulate: %{latency_ms: 80},
          policy: %{max_attempts: 2, backoff_ms: 5, timeout_ms: 10}
        },
        nil
      )

    assert {:ok, recorded} =
             eventually(fn ->
               case Ingest.replay("conv.effect.tool.execution.**", replay_start) do
                 {:ok, events} ->
                   lifecycles = effect_lifecycles(events, effect_id)

                   if includes_all?(lifecycles, ["started", "failed"]) do
                     {:ok, {:ok, events}}
                   else
                     :retry
                   end

                 other ->
                   {:ok, other}
               end
             end)

    assert Enum.any?(recorded, fn event ->
             effect_id_for(event) == effect_id and lifecycle_for(event) == "failed" and
               to_integer(data_field(event, :attempt, 0)) == 2
           end)

    eventually(fn ->
      if EffectManager.stats().in_flight_count == 0 do
        {:ok, :ok}
      else
        :retry
      end
    end)
  end

  test "llm effects execute through the configured backend and emit stream progress + completed lifecycle" do
    put_runtime_llm_backend!(LLMBackendStub, self())

    conversation_id = unique_id("conversation")
    effect_id = unique_id("effect")
    replay_start = DateTime.utc_now() |> DateTime.to_unix()

    :ok =
      EffectManager.start_effect(
        %{
          effect_id: effect_id,
          conversation_id: conversation_id,
          class: :llm,
          kind: "generation",
          input: %{content: "hello from test", role: "user"},
          policy: %{max_attempts: 1, backoff_ms: 5, timeout_ms: 1_000}
        },
        nil
      )

    assert_receive {:llm_backend_stream, %Request{} = request, _opts}
    assert request.conversation_id == conversation_id
    assert request.messages == [%{role: :user, content: "hello from test"}]

    assert {:ok, recorded} =
             eventually(fn ->
               case Ingest.replay("conv.effect.llm.generation.**", replay_start) do
                 {:ok, events} ->
                   events_for_effect =
                     Enum.filter(events, fn event ->
                       effect_id_for(event) == effect_id
                     end)

                   lifecycles =
                     events_for_effect
                     |> Enum.map(&lifecycle_for/1)
                     |> MapSet.new()

                   if MapSet.subset?(MapSet.new(["started", "progress", "completed"]), lifecycles) do
                     {:ok, {:ok, events_for_effect}}
                   else
                     :retry
                   end

                 other ->
                   {:ok, other}
               end
             end)

    assert Enum.any?(recorded, fn event ->
             lifecycle_for(event) == "progress" and
               data_field(event, :token_delta, nil) == "hello"
           end)

    assert Enum.any?(recorded, fn event ->
             lifecycle_for(event) == "progress" and
               data_field(event, :token_delta, nil) == "world"
           end)

    assert Enum.any?(recorded, fn event ->
             lifecycle_for(event) == "completed" and
               get_in(data_field(event, :result, %{}), [:text]) == "hello world"
           end)
  end

  test "llm effect execution updates runtime telemetry snapshot with lifecycle and stream metrics" do
    put_runtime_llm_backend!(LLMBackendStub, self())
    :ok = Telemetry.reset()
    baseline = Telemetry.snapshot().llm

    conversation_id = unique_id("conversation")
    effect_id = unique_id("effect")

    :ok =
      EffectManager.start_effect(
        %{
          effect_id: effect_id,
          conversation_id: conversation_id,
          class: :llm,
          kind: "generation",
          input: %{content: "telemetry path", role: "user"},
          policy: %{max_attempts: 1, backoff_ms: 5, timeout_ms: 1_000}
        },
        nil
      )

    assert_receive {:llm_backend_stream, %Request{}, _opts}

    snapshot =
      eventually(fn ->
        llm = Telemetry.snapshot().llm

        if llm.lifecycle_counts.started >= baseline.lifecycle_counts.started + 1 and
             llm.lifecycle_counts.completed >= baseline.lifecycle_counts.completed + 1 and
             llm.stream_chunks.total >= baseline.stream_chunks.total + 2 and
             llm.stream_duration_ms.count >= baseline.stream_duration_ms.count + 1 do
          {:ok, llm}
        else
          :retry
        end
      end)

    assert snapshot.lifecycle_by_backend["jido_ai"].completed >= 1
    assert snapshot.stream_chunks.delta >= baseline.stream_chunks.delta + 2
  end

  test "non-retryable llm backend stream-path errors do not retry and keep retry telemetry unchanged" do
    put_runtime_llm_backend!(LLMNonRetryableBackendStub, self())
    :ok = Telemetry.reset()
    baseline = Telemetry.snapshot().llm

    conversation_id = unique_id("conversation")
    effect_id = unique_id("effect")
    replay_start = DateTime.utc_now() |> DateTime.to_unix()

    :ok =
      EffectManager.start_effect(
        %{
          effect_id: effect_id,
          conversation_id: conversation_id,
          class: :llm,
          kind: "generation",
          input: %{content: "trigger non-retryable failure"},
          policy: %{max_attempts: 3, backoff_ms: 5, timeout_ms: 1_000}
        },
        nil
      )

    assert_receive {:llm_non_retryable_stream, %Request{}}
    refute_receive {:llm_non_retryable_stream, %Request{}}, 200

    assert {:ok, recorded} =
             eventually(fn ->
               case Ingest.replay("conv.effect.llm.generation.**", replay_start) do
                 {:ok, events} ->
                   events_for_effect = Enum.filter(events, &(effect_id_for(&1) == effect_id))
                   lifecycles = Enum.map(events_for_effect, &lifecycle_for/1) |> MapSet.new()

                   if MapSet.subset?(MapSet.new(["started", "failed"]), lifecycles) do
                     {:ok, {:ok, events_for_effect}}
                   else
                     :retry
                   end

                 other ->
                   {:ok, other}
               end
             end)

    assert Enum.count(recorded, &(lifecycle_for(&1) == "failed")) == 1
    assert Enum.count(recorded, &(lifecycle_for(&1) == "started")) == 1

    refute Enum.any?(recorded, fn event ->
             lifecycle_for(event) == "progress" and data_field(event, :status, nil) == "retrying"
           end)

    failed_event = Enum.find(recorded, &(lifecycle_for(&1) == "failed"))
    assert failed_event
    assert data_field(failed_event, :error_category, nil) == "config"
    assert data_field(failed_event, :retryable?, true) == false

    snapshot =
      eventually(fn ->
        llm = Telemetry.snapshot().llm

        if llm.lifecycle_counts.failed >= baseline.lifecycle_counts.failed + 1 do
          {:ok, llm}
        else
          :retry
        end
      end)

    assert Map.get(snapshot.retry_by_category, "config", 0) ==
             Map.get(baseline.retry_by_category, "config", 0)
  end

  test "non-retryable llm backend start-path errors do not retry and keep retry telemetry unchanged" do
    put_runtime_llm_backend!(LLMNonRetryableBackendStub, self(), false)
    :ok = Telemetry.reset()
    baseline = Telemetry.snapshot().llm

    conversation_id = unique_id("conversation")
    effect_id = unique_id("effect")
    replay_start = DateTime.utc_now() |> DateTime.to_unix()

    :ok =
      EffectManager.start_effect(
        %{
          effect_id: effect_id,
          conversation_id: conversation_id,
          class: :llm,
          kind: "generation",
          input: %{content: "trigger non-stream non-retryable failure"},
          policy: %{max_attempts: 3, backoff_ms: 5, timeout_ms: 1_000}
        },
        nil
      )

    assert_receive {:llm_non_retryable_start, %Request{}}
    refute_receive {:llm_non_retryable_start, %Request{}}, 200

    assert {:ok, recorded} =
             eventually(fn ->
               case Ingest.replay("conv.effect.llm.generation.**", replay_start) do
                 {:ok, events} ->
                   events_for_effect = Enum.filter(events, &(effect_id_for(&1) == effect_id))
                   lifecycles = Enum.map(events_for_effect, &lifecycle_for/1) |> MapSet.new()

                   if MapSet.subset?(MapSet.new(["started", "failed"]), lifecycles) do
                     {:ok, {:ok, events_for_effect}}
                   else
                     :retry
                   end

                 other ->
                   {:ok, other}
               end
             end)

    assert Enum.count(recorded, &(lifecycle_for(&1) == "failed")) == 1
    assert Enum.count(recorded, &(lifecycle_for(&1) == "started")) == 1

    refute Enum.any?(recorded, fn event ->
             lifecycle_for(event) == "progress" and data_field(event, :status, nil) == "retrying"
           end)

    failed_event = Enum.find(recorded, &(lifecycle_for(&1) == "failed"))
    assert failed_event
    assert data_field(failed_event, :error_category, nil) == "config"
    assert data_field(failed_event, :retryable?, true) == false

    snapshot =
      eventually(fn ->
        llm = Telemetry.snapshot().llm

        if llm.lifecycle_counts.failed >= baseline.lifecycle_counts.failed + 1 do
          {:ok, llm}
        else
          :retry
        end
      end)

    assert Map.get(snapshot.retry_by_category, "config", 0) ==
             Map.get(baseline.retry_by_category, "config", 0)
  end

  test "retryable llm backend stream-path errors retry with bounded attempts and recover without failed telemetry regressions" do
    put_runtime_llm_backend!(LLMRetryableProviderBackendStub, self())
    :ok = Telemetry.reset()
    baseline = Telemetry.snapshot().llm

    conversation_id = unique_id("conversation")
    effect_id = unique_id("effect")
    replay_start = DateTime.utc_now() |> DateTime.to_unix()

    :ok =
      EffectManager.start_effect(
        %{
          effect_id: effect_id,
          conversation_id: conversation_id,
          class: :llm,
          kind: "generation",
          input: %{content: "trigger retryable failure"},
          policy: %{max_attempts: 3, backoff_ms: 5, timeout_ms: 1_000}
        },
        nil
      )

    assert_receive {:llm_retryable_stream, %Request{}, 1}
    assert_receive {:llm_retryable_stream, %Request{}, 2}
    refute_receive {:llm_retryable_stream, %Request{}, 3}, 200

    assert {:ok, recorded} =
             eventually(fn ->
               case Ingest.replay("conv.effect.llm.generation.**", replay_start) do
                 {:ok, events} ->
                   events_for_effect = Enum.filter(events, &(effect_id_for(&1) == effect_id))

                   has_started? = Enum.any?(events_for_effect, &(lifecycle_for(&1) == "started"))

                   has_retrying_progress? =
                     Enum.any?(events_for_effect, fn event ->
                       lifecycle_for(event) == "progress" and
                         data_field(event, :status, nil) == "retrying"
                     end)

                   has_completed? =
                     Enum.any?(events_for_effect, &(lifecycle_for(&1) == "completed"))

                   if has_started? and has_retrying_progress? and has_completed? do
                     {:ok, {:ok, events_for_effect}}
                   else
                     :retry
                   end

                 other ->
                   {:ok, other}
               end
             end)

    retrying_event =
      Enum.find(recorded, fn event ->
        lifecycle_for(event) == "progress" and data_field(event, :status, nil) == "retrying"
      end)

    assert retrying_event
    assert data_field(retrying_event, :error_category, nil) == "provider"
    assert data_field(retrying_event, :retryable?, false) == true

    retry_attempt_started_event =
      Enum.find(recorded, fn event ->
        lifecycle_for(event) == "progress" and
          data_field(event, :status, nil) == "retry_attempt_started"
      end)

    assert retry_attempt_started_event
    assert to_integer(data_field(retry_attempt_started_event, :attempt, 0)) == 2
    assert Enum.count(recorded, &(lifecycle_for(&1) == "started")) == 1
    assert Enum.count(recorded, &(lifecycle_for(&1) == "completed")) == 1

    assert Enum.count(recorded, fn event ->
             lifecycle_for(event) == "progress" and data_field(event, :status, nil) == "retrying"
           end) == 1

    assert Enum.count(recorded, fn event ->
             lifecycle_for(event) == "progress" and
               data_field(event, :status, nil) == "retry_attempt_started"
           end) == 1

    assert Enum.any?(recorded, fn event ->
             lifecycle_for(event) == "completed" and
               get_in(data_field(event, :result, %{}), [:text]) == "recovered response"
           end)

    refute Enum.any?(recorded, &(lifecycle_for(&1) == "failed"))

    snapshot =
      eventually(fn ->
        llm = Telemetry.snapshot().llm

        if llm.lifecycle_counts.completed >= baseline.lifecycle_counts.completed + 1 and
             Map.get(llm.retry_by_category, "provider", 0) >=
               Map.get(baseline.retry_by_category, "provider", 0) + 1 do
          {:ok, llm}
        else
          :retry
        end
      end)

    assert Map.get(snapshot.retry_by_category, "provider", 0) ==
             Map.get(baseline.retry_by_category, "provider", 0) + 1

    assert snapshot.lifecycle_counts.failed == baseline.lifecycle_counts.failed
  end

  test "retryable llm backend start-path errors retry with bounded attempts and recover without failed telemetry regressions" do
    put_runtime_llm_backend!(LLMRetryableProviderBackendStub, self(), false)
    :ok = Telemetry.reset()
    baseline = Telemetry.snapshot().llm

    conversation_id = unique_id("conversation")
    effect_id = unique_id("effect")
    replay_start = DateTime.utc_now() |> DateTime.to_unix()

    :ok =
      EffectManager.start_effect(
        %{
          effect_id: effect_id,
          conversation_id: conversation_id,
          class: :llm,
          kind: "generation",
          input: %{content: "trigger non-stream retryable failure"},
          policy: %{max_attempts: 3, backoff_ms: 5, timeout_ms: 1_000}
        },
        nil
      )

    assert_receive {:llm_retryable_start, %Request{}, 1}
    assert_receive {:llm_retryable_start, %Request{}, 2}
    refute_receive {:llm_retryable_start, %Request{}, 3}, 200

    assert {:ok, recorded} =
             eventually(fn ->
               case Ingest.replay("conv.effect.llm.generation.**", replay_start) do
                 {:ok, events} ->
                   events_for_effect = Enum.filter(events, &(effect_id_for(&1) == effect_id))

                   has_started? = Enum.any?(events_for_effect, &(lifecycle_for(&1) == "started"))

                   has_retrying_progress? =
                     Enum.any?(events_for_effect, fn event ->
                       lifecycle_for(event) == "progress" and
                         data_field(event, :status, nil) == "retrying"
                     end)

                   has_completed? =
                     Enum.any?(events_for_effect, &(lifecycle_for(&1) == "completed"))

                   if has_started? and has_retrying_progress? and has_completed? do
                     {:ok, {:ok, events_for_effect}}
                   else
                     :retry
                   end

                 other ->
                   {:ok, other}
               end
             end)

    retrying_event =
      Enum.find(recorded, fn event ->
        lifecycle_for(event) == "progress" and data_field(event, :status, nil) == "retrying"
      end)

    assert retrying_event
    assert data_field(retrying_event, :error_category, nil) == "provider"
    assert data_field(retrying_event, :retryable?, false) == true

    retry_attempt_started_event =
      Enum.find(recorded, fn event ->
        lifecycle_for(event) == "progress" and
          data_field(event, :status, nil) == "retry_attempt_started"
      end)

    assert retry_attempt_started_event
    assert to_integer(data_field(retry_attempt_started_event, :attempt, 0)) == 2
    assert Enum.count(recorded, &(lifecycle_for(&1) == "started")) == 1
    assert Enum.count(recorded, &(lifecycle_for(&1) == "completed")) == 1

    assert Enum.count(recorded, fn event ->
             lifecycle_for(event) == "progress" and data_field(event, :status, nil) == "retrying"
           end) == 1

    assert Enum.count(recorded, fn event ->
             lifecycle_for(event) == "progress" and
               data_field(event, :status, nil) == "retry_attempt_started"
           end) == 1

    assert Enum.any?(recorded, fn event ->
             lifecycle_for(event) == "completed" and
               get_in(data_field(event, :result, %{}), [:text]) == "recovered response"
           end)

    refute Enum.any?(recorded, &(lifecycle_for(&1) == "failed"))

    snapshot =
      eventually(fn ->
        llm = Telemetry.snapshot().llm

        if llm.lifecycle_counts.completed >= baseline.lifecycle_counts.completed + 1 and
             Map.get(llm.retry_by_category, "provider", 0) >=
               Map.get(baseline.retry_by_category, "provider", 0) + 1 do
          {:ok, llm}
        else
          :retry
        end
      end)

    assert Map.get(snapshot.retry_by_category, "provider", 0) ==
             Map.get(baseline.retry_by_category, "provider", 0) + 1

    assert snapshot.lifecycle_counts.failed == baseline.lifecycle_counts.failed
  end

  test "cancel_conversation triggers llm backend cancel when execution_ref is available" do
    put_runtime_llm_backend!(LLMCancellableBackendStub, self())
    :ok = Telemetry.reset()
    baseline = Telemetry.snapshot().llm

    conversation_id = unique_id("conversation")
    effect_id = unique_id("effect")
    replay_start = DateTime.utc_now() |> DateTime.to_unix()

    :ok =
      EffectManager.start_effect(
        %{
          effect_id: effect_id,
          conversation_id: conversation_id,
          class: :llm,
          kind: "generation",
          input: %{content: "please run"},
          policy: %{max_attempts: 1, backoff_ms: 5, timeout_ms: 5_000}
        },
        nil
      )

    assert_receive {:llm_cancellable_stream, %Request{}, execution_ref}
    Process.sleep(50)

    :ok = EffectManager.cancel_conversation(conversation_id, "user_abort", nil)
    assert_receive {:llm_cancellable_cancel_called, :ok, ^execution_ref}

    assert {:ok, recorded} =
             eventually(fn ->
               case Ingest.replay("conv.effect.llm.generation.**", replay_start) do
                 {:ok, events} ->
                   events_for_effect = Enum.filter(events, &(effect_id_for(&1) == effect_id))
                   lifecycles = Enum.map(events_for_effect, &lifecycle_for/1)

                   if "canceled" in lifecycles do
                     {:ok, {:ok, events_for_effect}}
                   else
                     :retry
                   end

                 other ->
                   {:ok, other}
               end
             end)

    assert Enum.count(recorded, &(lifecycle_for(&1) == "started")) == 1
    assert Enum.count(recorded, &(lifecycle_for(&1) == "canceled")) == 1
    refute Enum.any?(recorded, &(lifecycle_for(&1) == "completed"))
    refute Enum.any?(recorded, &(lifecycle_for(&1) == "failed"))

    canceled_event = Enum.find(recorded, &(lifecycle_for(&1) == "canceled"))
    assert canceled_event
    assert data_field(canceled_event, :reason, nil) == "user_abort"
    assert data_field(canceled_event, :backend_cancel, nil) == "ok"

    snapshot =
      eventually(fn ->
        llm = Telemetry.snapshot().llm

        if llm.lifecycle_counts.canceled >= baseline.lifecycle_counts.canceled + 1 and
             Map.get(llm.cancel_results, "ok", 0) >=
               Map.get(baseline.cancel_results, "ok", 0) + 1 do
          {:ok, llm}
        else
          :retry
        end
      end)

    assert Map.get(snapshot.cancel_results, "ok", 0) >=
             Map.get(baseline.cancel_results, "ok", 0) + 1

    assert snapshot.retry_by_category == baseline.retry_by_category
  end

  test "cancel_conversation records ok cancel result on harness backend when execution_ref is available" do
    put_runtime_llm_backend_for!(:harness, LLMCancellableBackendStub, self())
    :ok = Telemetry.reset()
    baseline = Telemetry.snapshot().llm

    conversation_id = unique_id("conversation")
    effect_id = unique_id("effect")
    replay_start = DateTime.utc_now() |> DateTime.to_unix()

    :ok =
      EffectManager.start_effect(
        %{
          effect_id: effect_id,
          conversation_id: conversation_id,
          class: :llm,
          kind: "generation",
          input: %{content: "please run on harness"},
          policy: %{max_attempts: 1, backoff_ms: 5, timeout_ms: 5_000}
        },
        nil
      )

    assert_receive {:llm_cancellable_stream, %Request{backend: :harness}, execution_ref}
    assert is_pid(execution_ref)
    Process.sleep(50)

    :ok = EffectManager.cancel_conversation(conversation_id, "user_abort", nil)
    assert_receive {:llm_cancellable_cancel_called, :ok, ^execution_ref}

    canceled_event =
      eventually(fn ->
        case Ingest.replay("conv.effect.llm.generation.canceled", replay_start) do
          {:ok, events} ->
            events
            |> Enum.find(&(effect_id_for(&1) == effect_id and lifecycle_for(&1) == "canceled"))
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
    assert data_field(canceled_event, :backend, nil) == "harness"
    assert data_field(canceled_event, :provider, nil) == "stub-provider"
    assert data_field(canceled_event, :model, nil) == "stub-model"
    assert_terminal_canceled_only!(effect_id, replay_start)

    snapshot =
      eventually(fn ->
        llm = Telemetry.snapshot().llm

        if llm.lifecycle_counts.canceled >= baseline.lifecycle_counts.canceled + 1 and
             llm.cancel_latency_ms.count >= baseline.cancel_latency_ms.count + 1 and
             Map.get(llm.cancel_results, "ok", 0) >=
               Map.get(baseline.cancel_results, "ok", 0) + 1 do
          {:ok, llm}
        else
          :retry
        end
      end)

    assert Map.get(snapshot.cancel_results, "ok", 0) >=
             Map.get(baseline.cancel_results, "ok", 0) + 1

    assert backend_lifecycle_count(snapshot.lifecycle_by_backend, "harness", :canceled) >=
             backend_lifecycle_count(baseline.lifecycle_by_backend, "harness", :canceled) + 1

    assert snapshot.retry_by_category == baseline.retry_by_category
  end

  test "cancel_conversation records not_available cancel result on harness backend when execution_ref is missing" do
    put_runtime_llm_backend_for!(:harness, LLMCancellableBackendStub, self(), true,
      include_execution_ref?: false
    )

    :ok = Telemetry.reset()
    baseline = Telemetry.snapshot().llm

    conversation_id = unique_id("conversation")
    effect_id = unique_id("effect")
    replay_start = DateTime.utc_now() |> DateTime.to_unix()

    :ok =
      EffectManager.start_effect(
        %{
          effect_id: effect_id,
          conversation_id: conversation_id,
          class: :llm,
          kind: "generation",
          input: %{content: "please run on harness without execution ref"},
          policy: %{max_attempts: 1, backoff_ms: 5, timeout_ms: 5_000}
        },
        nil
      )

    assert_receive {:llm_cancellable_stream, %Request{backend: :harness}, nil}
    Process.sleep(50)

    :ok = EffectManager.cancel_conversation(conversation_id, "user_abort", nil)
    refute_receive {:llm_cancellable_cancel_called, _, _execution_ref}, 200

    canceled_event =
      eventually(fn ->
        case Ingest.replay("conv.effect.llm.generation.canceled", replay_start) do
          {:ok, events} ->
            events
            |> Enum.find(&(effect_id_for(&1) == effect_id and lifecycle_for(&1) == "canceled"))
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
    assert data_field(canceled_event, :backend, nil) == "harness"
    assert data_field(canceled_event, :provider, nil) == "stub-provider"
    assert data_field(canceled_event, :model, nil) == "stub-model"
    assert_terminal_canceled_only!(effect_id, replay_start)

    snapshot =
      eventually(fn ->
        llm = Telemetry.snapshot().llm

        if llm.lifecycle_counts.canceled >= baseline.lifecycle_counts.canceled + 1 and
             llm.cancel_latency_ms.count >= baseline.cancel_latency_ms.count + 1 and
             Map.get(llm.cancel_results, "not_available", 0) >=
               Map.get(baseline.cancel_results, "not_available", 0) + 1 do
          {:ok, llm}
        else
          :retry
        end
      end)

    assert Map.get(snapshot.cancel_results, "not_available", 0) >=
             Map.get(baseline.cancel_results, "not_available", 0) + 1

    assert backend_lifecycle_count(snapshot.lifecycle_by_backend, "harness", :canceled) >=
             backend_lifecycle_count(baseline.lifecycle_by_backend, "harness", :canceled) + 1

    assert snapshot.retry_by_category == baseline.retry_by_category
  end

  test "cancel_conversation links canceled lifecycle to explicit cause_id on harness backend when execution_ref is missing" do
    put_runtime_llm_backend_for!(:harness, LLMCancellableBackendStub, self(), true,
      include_execution_ref?: false
    )

    :ok = Telemetry.reset()
    baseline = Telemetry.snapshot().llm

    conversation_id = unique_id("conversation")
    effect_id = unique_id("effect")
    replay_start = DateTime.utc_now() |> DateTime.to_unix()

    assert {:ok, %{signal: cause_signal}} =
             Ingest.ingest(%{
               id: unique_id("cause"),
               type: "conv.audit.policy.decision_recorded",
               source: "/tests/effect-manager",
               subject: conversation_id,
               data: %{audit_id: unique_id("audit"), category: "policy", decision: "allow"},
               extensions: %{contract_major: 1}
             })

    :ok =
      EffectManager.start_effect(
        %{
          effect_id: effect_id,
          conversation_id: conversation_id,
          class: :llm,
          kind: "generation",
          input: %{content: "please run on harness without execution ref and explicit cause"},
          policy: %{max_attempts: 1, backoff_ms: 5, timeout_ms: 5_000}
        },
        nil
      )

    assert_receive {:llm_cancellable_stream, %Request{backend: :harness}, nil}
    Process.sleep(50)

    :ok = EffectManager.cancel_conversation(conversation_id, "user_abort", cause_signal.id)
    refute_receive {:llm_cancellable_cancel_called, _, _execution_ref}, 200

    canceled_events =
      eventually(fn ->
        case Ingest.replay("conv.effect.llm.generation.canceled", replay_start) do
          {:ok, events} ->
            matches = Enum.filter(events, &(effect_id_for(&1) == effect_id))
            if matches == [], do: :retry, else: {:ok, matches}

          _other ->
            :retry
        end
      end)

    assert Enum.count(canceled_events, &(lifecycle_for(&1) == "canceled")) == 1
    canceled_event = Enum.find(canceled_events, &(lifecycle_for(&1) == "canceled"))
    assert canceled_event
    assert data_field(canceled_event, :reason, nil) == "user_abort"
    assert data_field(canceled_event, :backend_cancel, nil) == "not_available"
    assert data_field(canceled_event, :backend, nil) == "harness"
    assert data_field(canceled_event, :provider, nil) == "stub-provider"
    assert data_field(canceled_event, :model, nil) == "stub-model"

    trace = Ingest.trace_chain(canceled_event.signal.id, :backward)
    trace_ids = Enum.map(trace, & &1.id)

    assert canceled_event.signal.id in trace_ids
    assert cause_signal.id in trace_ids
    assert_terminal_canceled_only!(effect_id, replay_start)

    snapshot =
      eventually(fn ->
        llm = Telemetry.snapshot().llm

        if llm.lifecycle_counts.canceled >= baseline.lifecycle_counts.canceled + 1 and
             llm.cancel_latency_ms.count >= baseline.cancel_latency_ms.count + 1 and
             Map.get(llm.cancel_results, "not_available", 0) >=
               Map.get(baseline.cancel_results, "not_available", 0) + 1 do
          {:ok, llm}
        else
          :retry
        end
      end)

    assert Map.get(snapshot.cancel_results, "not_available", 0) >=
             Map.get(baseline.cancel_results, "not_available", 0) + 1

    assert backend_lifecycle_count(snapshot.lifecycle_by_backend, "harness", :canceled) >=
             backend_lifecycle_count(baseline.lifecycle_by_backend, "harness", :canceled) + 1

    assert snapshot.retry_by_category == baseline.retry_by_category
  end

  test "cancel_conversation falls back to uncoupled canceled lifecycle when cause_id is invalid on harness backend and execution_ref is missing" do
    put_runtime_llm_backend_for!(:harness, LLMCancellableBackendStub, self(), true,
      include_execution_ref?: false
    )

    :ok = Telemetry.reset()
    baseline = Telemetry.snapshot().llm

    conversation_id = unique_id("conversation")
    effect_id = unique_id("effect")
    replay_start = DateTime.utc_now() |> DateTime.to_unix()
    invalid_cause_id = unique_id("unknown-cause")

    :ok =
      EffectManager.start_effect(
        %{
          effect_id: effect_id,
          conversation_id: conversation_id,
          class: :llm,
          kind: "generation",
          input: %{content: "please run on harness without execution ref and invalid cause"},
          policy: %{max_attempts: 1, backoff_ms: 5, timeout_ms: 5_000}
        },
        nil
      )

    assert_receive {:llm_cancellable_stream, %Request{backend: :harness}, nil}
    Process.sleep(50)

    :ok = EffectManager.cancel_conversation(conversation_id, "user_abort", invalid_cause_id)
    refute_receive {:llm_cancellable_cancel_called, _, _execution_ref}, 200

    canceled_events =
      eventually(fn ->
        case Ingest.replay("conv.effect.llm.generation.canceled", replay_start) do
          {:ok, events} ->
            matches = Enum.filter(events, &(effect_id_for(&1) == effect_id))
            if matches == [], do: :retry, else: {:ok, matches}

          _other ->
            :retry
        end
      end)

    assert Enum.count(canceled_events, &(lifecycle_for(&1) == "canceled")) == 1
    canceled_event = Enum.find(canceled_events, &(lifecycle_for(&1) == "canceled"))
    assert canceled_event
    assert data_field(canceled_event, :reason, nil) == "user_abort"
    assert data_field(canceled_event, :backend_cancel, nil) == "not_available"
    assert data_field(canceled_event, :backend, nil) == "harness"
    assert data_field(canceled_event, :provider, nil) == "stub-provider"
    assert data_field(canceled_event, :model, nil) == "stub-model"

    trace = Ingest.trace_chain(canceled_event.signal.id, :backward)
    trace_ids = Enum.map(trace, & &1.id)

    assert canceled_event.signal.id in trace_ids
    refute invalid_cause_id in trace_ids
    assert_terminal_canceled_only!(effect_id, replay_start)

    snapshot =
      eventually(fn ->
        llm = Telemetry.snapshot().llm

        if llm.lifecycle_counts.canceled >= baseline.lifecycle_counts.canceled + 1 and
             llm.cancel_latency_ms.count >= baseline.cancel_latency_ms.count + 1 and
             Map.get(llm.cancel_results, "not_available", 0) >=
               Map.get(baseline.cancel_results, "not_available", 0) + 1 do
          {:ok, llm}
        else
          :retry
        end
      end)

    assert Map.get(snapshot.cancel_results, "not_available", 0) >=
             Map.get(baseline.cancel_results, "not_available", 0) + 1

    assert backend_lifecycle_count(snapshot.lifecycle_by_backend, "harness", :canceled) >=
             backend_lifecycle_count(baseline.lifecycle_by_backend, "harness", :canceled) + 1

    assert snapshot.retry_by_category == baseline.retry_by_category
  end

  test "cancel_conversation records failed cancel result on harness backend when backend cancellation fails" do
    put_runtime_llm_backend_for!(:harness, LLMCancellableBackendStub, self(), true,
      cancel_scenario: :failed
    )

    :ok = Telemetry.reset()
    baseline = Telemetry.snapshot().llm

    conversation_id = unique_id("conversation")
    effect_id = unique_id("effect")
    replay_start = DateTime.utc_now() |> DateTime.to_unix()

    :ok =
      EffectManager.start_effect(
        %{
          effect_id: effect_id,
          conversation_id: conversation_id,
          class: :llm,
          kind: "generation",
          input: %{content: "please run on harness with failing cancel"},
          policy: %{max_attempts: 1, backoff_ms: 5, timeout_ms: 5_000}
        },
        nil
      )

    assert_receive {:llm_cancellable_stream, %Request{backend: :harness}, execution_ref}
    assert is_pid(execution_ref)
    Process.sleep(50)

    :ok = EffectManager.cancel_conversation(conversation_id, "user_abort", nil)
    assert_receive {:llm_cancellable_cancel_called, :failed, ^execution_ref}

    assert {:ok, recorded} =
             eventually(fn ->
               case Ingest.replay("conv.effect.llm.generation.**", replay_start) do
                 {:ok, events} ->
                   events_for_effect = Enum.filter(events, &(effect_id_for(&1) == effect_id))
                   lifecycles = Enum.map(events_for_effect, &lifecycle_for/1)

                   if "canceled" in lifecycles do
                     {:ok, {:ok, events_for_effect}}
                   else
                     :retry
                   end

                 other ->
                   {:ok, other}
               end
             end)

    assert Enum.count(recorded, &(lifecycle_for(&1) == "started")) == 1
    assert Enum.count(recorded, &(lifecycle_for(&1) == "canceled")) == 1
    refute Enum.any?(recorded, &(lifecycle_for(&1) == "completed"))
    refute Enum.any?(recorded, &(lifecycle_for(&1) == "failed"))

    canceled_event = Enum.find(recorded, &(lifecycle_for(&1) == "canceled"))
    assert canceled_event
    assert data_field(canceled_event, :reason, nil) == "user_abort"
    assert data_field(canceled_event, :backend_cancel, nil) == "failed"
    assert data_field(canceled_event, :backend_cancel_reason, nil) == "cancel failed"
    assert data_field(canceled_event, :backend_cancel_category, nil) == "provider"
    assert data_field(canceled_event, :backend_cancel_retryable?, nil) == true
    assert data_field(canceled_event, :backend, nil) == "harness"
    assert data_field(canceled_event, :provider, nil) == "stub-provider"
    assert data_field(canceled_event, :model, nil) == "stub-model"
    assert_terminal_canceled_only!(effect_id, replay_start)

    snapshot =
      eventually(fn ->
        llm = Telemetry.snapshot().llm

        if llm.lifecycle_counts.canceled >= baseline.lifecycle_counts.canceled + 1 and
             llm.cancel_latency_ms.count >= baseline.cancel_latency_ms.count + 1 and
             Map.get(llm.cancel_results, "failed", 0) >=
               Map.get(baseline.cancel_results, "failed", 0) + 1 do
          {:ok, llm}
        else
          :retry
        end
      end)

    assert Map.get(snapshot.cancel_results, "failed", 0) >=
             Map.get(baseline.cancel_results, "failed", 0) + 1

    assert backend_lifecycle_count(snapshot.lifecycle_by_backend, "harness", :canceled) >=
             backend_lifecycle_count(baseline.lifecycle_by_backend, "harness", :canceled) + 1

    assert snapshot.retry_by_category == baseline.retry_by_category
  end

  test "cancel_conversation links canceled lifecycle to explicit cause_id on harness backend when backend cancellation fails" do
    put_runtime_llm_backend_for!(:harness, LLMCancellableBackendStub, self(), true,
      cancel_scenario: :failed
    )

    :ok = Telemetry.reset()
    baseline = Telemetry.snapshot().llm

    conversation_id = unique_id("conversation")
    effect_id = unique_id("effect")
    replay_start = DateTime.utc_now() |> DateTime.to_unix()

    assert {:ok, %{signal: cause_signal}} =
             Ingest.ingest(%{
               id: unique_id("cause"),
               type: "conv.audit.policy.decision_recorded",
               source: "/tests/effect-manager",
               subject: conversation_id,
               data: %{audit_id: unique_id("audit"), category: "policy", decision: "allow"},
               extensions: %{contract_major: 1}
             })

    :ok =
      EffectManager.start_effect(
        %{
          effect_id: effect_id,
          conversation_id: conversation_id,
          class: :llm,
          kind: "generation",
          input: %{content: "please run on harness with failed cancel and explicit cause"},
          policy: %{max_attempts: 1, backoff_ms: 5, timeout_ms: 5_000}
        },
        nil
      )

    assert_receive {:llm_cancellable_stream, %Request{backend: :harness}, execution_ref}
    assert is_pid(execution_ref)
    Process.sleep(50)

    :ok = EffectManager.cancel_conversation(conversation_id, "user_abort", cause_signal.id)
    assert_receive {:llm_cancellable_cancel_called, :failed, ^execution_ref}

    canceled_events =
      eventually(fn ->
        case Ingest.replay("conv.effect.llm.generation.canceled", replay_start) do
          {:ok, events} ->
            matches = Enum.filter(events, &(effect_id_for(&1) == effect_id))
            if matches == [], do: :retry, else: {:ok, matches}

          _other ->
            :retry
        end
      end)

    assert Enum.count(canceled_events, &(lifecycle_for(&1) == "canceled")) == 1
    canceled_event = Enum.find(canceled_events, &(lifecycle_for(&1) == "canceled"))
    assert canceled_event
    assert data_field(canceled_event, :reason, nil) == "user_abort"
    assert data_field(canceled_event, :backend_cancel, nil) == "failed"
    assert data_field(canceled_event, :backend_cancel_reason, nil) == "cancel failed"
    assert data_field(canceled_event, :backend_cancel_category, nil) == "provider"
    assert data_field(canceled_event, :backend_cancel_retryable?, nil) == true
    assert data_field(canceled_event, :backend, nil) == "harness"
    assert data_field(canceled_event, :provider, nil) == "stub-provider"
    assert data_field(canceled_event, :model, nil) == "stub-model"

    trace = Ingest.trace_chain(canceled_event.signal.id, :backward)
    trace_ids = Enum.map(trace, & &1.id)

    assert canceled_event.signal.id in trace_ids
    assert cause_signal.id in trace_ids
    assert_terminal_canceled_only!(effect_id, replay_start)

    snapshot =
      eventually(fn ->
        llm = Telemetry.snapshot().llm

        if llm.lifecycle_counts.canceled >= baseline.lifecycle_counts.canceled + 1 and
             llm.cancel_latency_ms.count >= baseline.cancel_latency_ms.count + 1 and
             Map.get(llm.cancel_results, "failed", 0) >=
               Map.get(baseline.cancel_results, "failed", 0) + 1 do
          {:ok, llm}
        else
          :retry
        end
      end)

    assert Map.get(snapshot.cancel_results, "failed", 0) >=
             Map.get(baseline.cancel_results, "failed", 0) + 1

    assert backend_lifecycle_count(snapshot.lifecycle_by_backend, "harness", :canceled) >=
             backend_lifecycle_count(baseline.lifecycle_by_backend, "harness", :canceled) + 1

    assert snapshot.retry_by_category == baseline.retry_by_category
  end

  test "cancel_conversation falls back to uncoupled canceled lifecycle when cause_id is invalid on harness backend and backend cancellation fails" do
    put_runtime_llm_backend_for!(:harness, LLMCancellableBackendStub, self(), true,
      cancel_scenario: :failed
    )

    :ok = Telemetry.reset()
    baseline = Telemetry.snapshot().llm

    conversation_id = unique_id("conversation")
    effect_id = unique_id("effect")
    replay_start = DateTime.utc_now() |> DateTime.to_unix()
    invalid_cause_id = unique_id("unknown-cause")

    :ok =
      EffectManager.start_effect(
        %{
          effect_id: effect_id,
          conversation_id: conversation_id,
          class: :llm,
          kind: "generation",
          input: %{content: "please run on harness with failed cancel and invalid cause"},
          policy: %{max_attempts: 1, backoff_ms: 5, timeout_ms: 5_000}
        },
        nil
      )

    assert_receive {:llm_cancellable_stream, %Request{backend: :harness}, execution_ref}
    assert is_pid(execution_ref)
    Process.sleep(50)

    :ok = EffectManager.cancel_conversation(conversation_id, "user_abort", invalid_cause_id)
    assert_receive {:llm_cancellable_cancel_called, :failed, ^execution_ref}

    canceled_events =
      eventually(fn ->
        case Ingest.replay("conv.effect.llm.generation.canceled", replay_start) do
          {:ok, events} ->
            matches = Enum.filter(events, &(effect_id_for(&1) == effect_id))
            if matches == [], do: :retry, else: {:ok, matches}

          _other ->
            :retry
        end
      end)

    assert Enum.count(canceled_events, &(lifecycle_for(&1) == "canceled")) == 1
    canceled_event = Enum.find(canceled_events, &(lifecycle_for(&1) == "canceled"))
    assert canceled_event
    assert data_field(canceled_event, :reason, nil) == "user_abort"
    assert data_field(canceled_event, :backend_cancel, nil) == "failed"
    assert data_field(canceled_event, :backend_cancel_reason, nil) == "cancel failed"
    assert data_field(canceled_event, :backend_cancel_category, nil) == "provider"
    assert data_field(canceled_event, :backend_cancel_retryable?, nil) == true
    assert data_field(canceled_event, :backend, nil) == "harness"
    assert data_field(canceled_event, :provider, nil) == "stub-provider"
    assert data_field(canceled_event, :model, nil) == "stub-model"

    trace = Ingest.trace_chain(canceled_event.signal.id, :backward)
    trace_ids = Enum.map(trace, & &1.id)

    assert canceled_event.signal.id in trace_ids
    refute invalid_cause_id in trace_ids
    assert_terminal_canceled_only!(effect_id, replay_start)

    snapshot =
      eventually(fn ->
        llm = Telemetry.snapshot().llm

        if llm.lifecycle_counts.canceled >= baseline.lifecycle_counts.canceled + 1 and
             llm.cancel_latency_ms.count >= baseline.cancel_latency_ms.count + 1 and
             Map.get(llm.cancel_results, "failed", 0) >=
               Map.get(baseline.cancel_results, "failed", 0) + 1 do
          {:ok, llm}
        else
          :retry
        end
      end)

    assert Map.get(snapshot.cancel_results, "failed", 0) >=
             Map.get(baseline.cancel_results, "failed", 0) + 1

    assert backend_lifecycle_count(snapshot.lifecycle_by_backend, "harness", :canceled) >=
             backend_lifecycle_count(baseline.lifecycle_by_backend, "harness", :canceled) + 1

    assert snapshot.retry_by_category == baseline.retry_by_category
  end

  test "cancel_conversation links canceled lifecycle to explicit cause_id on harness backend" do
    put_runtime_llm_backend_for!(:harness, LLMCancellableBackendStub, self())
    :ok = Telemetry.reset()
    baseline = Telemetry.snapshot().llm

    conversation_id = unique_id("conversation")
    effect_id = unique_id("effect")
    replay_start = DateTime.utc_now() |> DateTime.to_unix()

    assert {:ok, %{signal: cause_signal}} =
             Ingest.ingest(%{
               id: unique_id("cause"),
               type: "conv.audit.policy.decision_recorded",
               source: "/tests/effect-manager",
               subject: conversation_id,
               data: %{audit_id: unique_id("audit"), category: "policy", decision: "allow"},
               extensions: %{contract_major: 1}
             })

    :ok =
      EffectManager.start_effect(
        %{
          effect_id: effect_id,
          conversation_id: conversation_id,
          class: :llm,
          kind: "generation",
          input: %{content: "please run on harness with explicit cancel cause"},
          policy: %{max_attempts: 1, backoff_ms: 5, timeout_ms: 5_000}
        },
        nil
      )

    assert_receive {:llm_cancellable_stream, %Request{backend: :harness}, execution_ref}
    assert is_pid(execution_ref)
    Process.sleep(50)

    :ok = EffectManager.cancel_conversation(conversation_id, "user_abort", cause_signal.id)
    assert_receive {:llm_cancellable_cancel_called, :ok, ^execution_ref}

    canceled_events =
      eventually(fn ->
        case Ingest.replay("conv.effect.llm.generation.canceled", replay_start) do
          {:ok, events} ->
            matches = Enum.filter(events, &(effect_id_for(&1) == effect_id))
            if matches == [], do: :retry, else: {:ok, matches}

          _other ->
            :retry
        end
      end)

    assert Enum.count(canceled_events, &(lifecycle_for(&1) == "canceled")) == 1
    canceled_event = Enum.find(canceled_events, &(lifecycle_for(&1) == "canceled"))
    assert canceled_event
    assert data_field(canceled_event, :reason, nil) == "user_abort"
    assert data_field(canceled_event, :backend_cancel, nil) == "ok"
    assert data_field(canceled_event, :backend, nil) == "harness"
    assert data_field(canceled_event, :provider, nil) == "stub-provider"
    assert data_field(canceled_event, :model, nil) == "stub-model"

    trace = Ingest.trace_chain(canceled_event.signal.id, :backward)
    trace_ids = Enum.map(trace, & &1.id)

    assert canceled_event.signal.id in trace_ids
    assert cause_signal.id in trace_ids
    assert_terminal_canceled_only!(effect_id, replay_start)

    snapshot =
      eventually(fn ->
        llm = Telemetry.snapshot().llm

        if llm.lifecycle_counts.canceled >= baseline.lifecycle_counts.canceled + 1 and
             llm.cancel_latency_ms.count >= baseline.cancel_latency_ms.count + 1 and
             Map.get(llm.cancel_results, "ok", 0) >=
               Map.get(baseline.cancel_results, "ok", 0) + 1 do
          {:ok, llm}
        else
          :retry
        end
      end)

    assert Map.get(snapshot.cancel_results, "ok", 0) >=
             Map.get(baseline.cancel_results, "ok", 0) + 1

    assert backend_lifecycle_count(snapshot.lifecycle_by_backend, "harness", :canceled) >=
             backend_lifecycle_count(baseline.lifecycle_by_backend, "harness", :canceled) + 1

    assert snapshot.retry_by_category == baseline.retry_by_category
  end

  test "cancel_conversation falls back to uncoupled canceled lifecycle when cause_id is invalid on harness backend" do
    put_runtime_llm_backend_for!(:harness, LLMCancellableBackendStub, self())
    :ok = Telemetry.reset()
    baseline = Telemetry.snapshot().llm

    conversation_id = unique_id("conversation")
    effect_id = unique_id("effect")
    replay_start = DateTime.utc_now() |> DateTime.to_unix()
    invalid_cause_id = unique_id("unknown-cause")

    :ok =
      EffectManager.start_effect(
        %{
          effect_id: effect_id,
          conversation_id: conversation_id,
          class: :llm,
          kind: "generation",
          input: %{content: "please run on harness with invalid cancel cause"},
          policy: %{max_attempts: 1, backoff_ms: 5, timeout_ms: 5_000}
        },
        nil
      )

    assert_receive {:llm_cancellable_stream, %Request{backend: :harness}, execution_ref}
    assert is_pid(execution_ref)
    Process.sleep(50)

    :ok = EffectManager.cancel_conversation(conversation_id, "user_abort", invalid_cause_id)
    assert_receive {:llm_cancellable_cancel_called, :ok, ^execution_ref}

    canceled_events =
      eventually(fn ->
        case Ingest.replay("conv.effect.llm.generation.canceled", replay_start) do
          {:ok, events} ->
            matches = Enum.filter(events, &(effect_id_for(&1) == effect_id))
            if matches == [], do: :retry, else: {:ok, matches}

          _other ->
            :retry
        end
      end)

    assert Enum.count(canceled_events, &(lifecycle_for(&1) == "canceled")) == 1
    canceled_event = Enum.find(canceled_events, &(lifecycle_for(&1) == "canceled"))
    assert canceled_event
    assert data_field(canceled_event, :reason, nil) == "user_abort"
    assert data_field(canceled_event, :backend_cancel, nil) == "ok"
    assert data_field(canceled_event, :backend, nil) == "harness"
    assert data_field(canceled_event, :provider, nil) == "stub-provider"
    assert data_field(canceled_event, :model, nil) == "stub-model"

    trace = Ingest.trace_chain(canceled_event.signal.id, :backward)
    trace_ids = Enum.map(trace, & &1.id)

    assert canceled_event.signal.id in trace_ids
    refute invalid_cause_id in trace_ids
    assert_terminal_canceled_only!(effect_id, replay_start)

    snapshot =
      eventually(fn ->
        llm = Telemetry.snapshot().llm

        if llm.lifecycle_counts.canceled >= baseline.lifecycle_counts.canceled + 1 and
             llm.cancel_latency_ms.count >= baseline.cancel_latency_ms.count + 1 and
             Map.get(llm.cancel_results, "ok", 0) >=
               Map.get(baseline.cancel_results, "ok", 0) + 1 do
          {:ok, llm}
        else
          :retry
        end
      end)

    assert Map.get(snapshot.cancel_results, "ok", 0) >=
             Map.get(baseline.cancel_results, "ok", 0) + 1

    assert backend_lifecycle_count(snapshot.lifecycle_by_backend, "harness", :canceled) >=
             backend_lifecycle_count(baseline.lifecycle_by_backend, "harness", :canceled) + 1

    assert snapshot.retry_by_category == baseline.retry_by_category
  end

  test "cancel_conversation records not_available cancel result when execution_ref is missing" do
    put_runtime_llm_backend!(LLMCancellableBackendStub, self(), true,
      include_execution_ref?: false
    )

    :ok = Telemetry.reset()
    baseline = Telemetry.snapshot().llm

    conversation_id = unique_id("conversation")
    effect_id = unique_id("effect")
    replay_start = DateTime.utc_now() |> DateTime.to_unix()

    :ok =
      EffectManager.start_effect(
        %{
          effect_id: effect_id,
          conversation_id: conversation_id,
          class: :llm,
          kind: "generation",
          input: %{content: "please run without execution ref"},
          policy: %{max_attempts: 1, backoff_ms: 5, timeout_ms: 5_000}
        },
        nil
      )

    assert_receive {:llm_cancellable_stream, %Request{}, nil}
    Process.sleep(50)

    :ok = EffectManager.cancel_conversation(conversation_id, "user_abort", nil)
    refute_receive {:llm_cancellable_cancel_called, _, _execution_ref}, 200

    assert {:ok, recorded} =
             eventually(fn ->
               case Ingest.replay("conv.effect.llm.generation.**", replay_start) do
                 {:ok, events} ->
                   events_for_effect = Enum.filter(events, &(effect_id_for(&1) == effect_id))
                   lifecycles = Enum.map(events_for_effect, &lifecycle_for/1)

                   if "canceled" in lifecycles do
                     {:ok, {:ok, events_for_effect}}
                   else
                     :retry
                   end

                 other ->
                   {:ok, other}
               end
             end)

    assert Enum.count(recorded, &(lifecycle_for(&1) == "started")) == 1
    assert Enum.count(recorded, &(lifecycle_for(&1) == "canceled")) == 1
    refute Enum.any?(recorded, &(lifecycle_for(&1) == "completed"))
    refute Enum.any?(recorded, &(lifecycle_for(&1) == "failed"))

    canceled_event = Enum.find(recorded, &(lifecycle_for(&1) == "canceled"))
    assert canceled_event
    assert data_field(canceled_event, :reason, nil) == "user_abort"
    assert data_field(canceled_event, :backend_cancel, nil) == "not_available"

    snapshot =
      eventually(fn ->
        llm = Telemetry.snapshot().llm

        if llm.lifecycle_counts.canceled >= baseline.lifecycle_counts.canceled + 1 and
             llm.cancel_latency_ms.count >= baseline.cancel_latency_ms.count + 1 and
             Map.get(llm.cancel_results, "not_available", 0) >=
               Map.get(baseline.cancel_results, "not_available", 0) + 1 do
          {:ok, llm}
        else
          :retry
        end
      end)

    assert Map.get(snapshot.cancel_results, "not_available", 0) >=
             Map.get(baseline.cancel_results, "not_available", 0) + 1

    assert snapshot.retry_by_category == baseline.retry_by_category
  end

  test "cancel_conversation links canceled lifecycle to explicit cause_id when execution_ref is missing" do
    put_runtime_llm_backend!(LLMCancellableBackendStub, self(), true,
      include_execution_ref?: false
    )

    :ok = Telemetry.reset()
    baseline = Telemetry.snapshot().llm

    conversation_id = unique_id("conversation")
    effect_id = unique_id("effect")
    replay_start = DateTime.utc_now() |> DateTime.to_unix()

    assert {:ok, %{signal: cause_signal}} =
             Ingest.ingest(%{
               id: unique_id("cause"),
               type: "conv.audit.policy.decision_recorded",
               source: "/tests/effect-manager",
               subject: conversation_id,
               data: %{audit_id: unique_id("audit"), category: "policy", decision: "allow"},
               extensions: %{contract_major: 1}
             })

    :ok =
      EffectManager.start_effect(
        %{
          effect_id: effect_id,
          conversation_id: conversation_id,
          class: :llm,
          kind: "generation",
          input: %{content: "please run without execution ref and explicit cause"},
          policy: %{max_attempts: 1, backoff_ms: 5, timeout_ms: 5_000}
        },
        nil
      )

    assert_receive {:llm_cancellable_stream, %Request{}, nil}
    Process.sleep(50)

    :ok = EffectManager.cancel_conversation(conversation_id, "user_abort", cause_signal.id)
    refute_receive {:llm_cancellable_cancel_called, _, _execution_ref}, 200

    canceled_events =
      eventually(fn ->
        case Ingest.replay("conv.effect.llm.generation.canceled", replay_start) do
          {:ok, events} ->
            matches = Enum.filter(events, &(effect_id_for(&1) == effect_id))
            if matches == [], do: :retry, else: {:ok, matches}

          _other ->
            :retry
        end
      end)

    assert Enum.count(canceled_events, &(lifecycle_for(&1) == "canceled")) == 1
    canceled_event = Enum.find(canceled_events, &(lifecycle_for(&1) == "canceled"))
    assert canceled_event
    assert data_field(canceled_event, :reason, nil) == "user_abort"
    assert data_field(canceled_event, :backend_cancel, nil) == "not_available"
    assert data_field(canceled_event, :backend, nil) == "jido_ai"
    assert data_field(canceled_event, :provider, nil) == "stub-provider"
    assert data_field(canceled_event, :model, nil) == "stub-model"

    trace = Ingest.trace_chain(canceled_event.signal.id, :backward)
    trace_ids = Enum.map(trace, & &1.id)

    assert canceled_event.signal.id in trace_ids
    assert cause_signal.id in trace_ids
    assert_terminal_canceled_only!(effect_id, replay_start)

    snapshot =
      eventually(fn ->
        llm = Telemetry.snapshot().llm

        if llm.lifecycle_counts.canceled >= baseline.lifecycle_counts.canceled + 1 and
             llm.cancel_latency_ms.count >= baseline.cancel_latency_ms.count + 1 and
             Map.get(llm.cancel_results, "not_available", 0) >=
               Map.get(baseline.cancel_results, "not_available", 0) + 1 do
          {:ok, llm}
        else
          :retry
        end
      end)

    assert Map.get(snapshot.cancel_results, "not_available", 0) >=
             Map.get(baseline.cancel_results, "not_available", 0) + 1

    assert backend_lifecycle_count(snapshot.lifecycle_by_backend, "jido_ai", :canceled) >=
             backend_lifecycle_count(baseline.lifecycle_by_backend, "jido_ai", :canceled) + 1

    assert snapshot.retry_by_category == baseline.retry_by_category
  end

  test "cancel_conversation falls back to uncoupled canceled lifecycle when cause_id is invalid and execution_ref is missing" do
    put_runtime_llm_backend!(LLMCancellableBackendStub, self(), true,
      include_execution_ref?: false
    )

    :ok = Telemetry.reset()
    baseline = Telemetry.snapshot().llm

    conversation_id = unique_id("conversation")
    effect_id = unique_id("effect")
    replay_start = DateTime.utc_now() |> DateTime.to_unix()
    invalid_cause_id = unique_id("unknown-cause")

    :ok =
      EffectManager.start_effect(
        %{
          effect_id: effect_id,
          conversation_id: conversation_id,
          class: :llm,
          kind: "generation",
          input: %{content: "please run without execution ref and invalid cause"},
          policy: %{max_attempts: 1, backoff_ms: 5, timeout_ms: 5_000}
        },
        nil
      )

    assert_receive {:llm_cancellable_stream, %Request{}, nil}
    Process.sleep(50)

    :ok = EffectManager.cancel_conversation(conversation_id, "user_abort", invalid_cause_id)
    refute_receive {:llm_cancellable_cancel_called, _, _execution_ref}, 200

    canceled_events =
      eventually(fn ->
        case Ingest.replay("conv.effect.llm.generation.canceled", replay_start) do
          {:ok, events} ->
            matches = Enum.filter(events, &(effect_id_for(&1) == effect_id))
            if matches == [], do: :retry, else: {:ok, matches}

          _other ->
            :retry
        end
      end)

    assert Enum.count(canceled_events, &(lifecycle_for(&1) == "canceled")) == 1
    canceled_event = Enum.find(canceled_events, &(lifecycle_for(&1) == "canceled"))
    assert canceled_event
    assert data_field(canceled_event, :reason, nil) == "user_abort"
    assert data_field(canceled_event, :backend_cancel, nil) == "not_available"
    assert data_field(canceled_event, :backend, nil) == "jido_ai"
    assert data_field(canceled_event, :provider, nil) == "stub-provider"
    assert data_field(canceled_event, :model, nil) == "stub-model"

    trace = Ingest.trace_chain(canceled_event.signal.id, :backward)
    trace_ids = Enum.map(trace, & &1.id)

    assert canceled_event.signal.id in trace_ids
    refute invalid_cause_id in trace_ids
    assert_terminal_canceled_only!(effect_id, replay_start)

    snapshot =
      eventually(fn ->
        llm = Telemetry.snapshot().llm

        if llm.lifecycle_counts.canceled >= baseline.lifecycle_counts.canceled + 1 and
             llm.cancel_latency_ms.count >= baseline.cancel_latency_ms.count + 1 and
             Map.get(llm.cancel_results, "not_available", 0) >=
               Map.get(baseline.cancel_results, "not_available", 0) + 1 do
          {:ok, llm}
        else
          :retry
        end
      end)

    assert Map.get(snapshot.cancel_results, "not_available", 0) >=
             Map.get(baseline.cancel_results, "not_available", 0) + 1

    assert backend_lifecycle_count(snapshot.lifecycle_by_backend, "jido_ai", :canceled) >=
             backend_lifecycle_count(baseline.lifecycle_by_backend, "jido_ai", :canceled) + 1

    assert snapshot.retry_by_category == baseline.retry_by_category
  end

  test "cancel_conversation records failed cancel result when backend cancellation fails" do
    put_runtime_llm_backend!(LLMCancellableBackendStub, self(), true, cancel_scenario: :failed)
    :ok = Telemetry.reset()
    baseline = Telemetry.snapshot().llm

    conversation_id = unique_id("conversation")
    effect_id = unique_id("effect")
    replay_start = DateTime.utc_now() |> DateTime.to_unix()

    :ok =
      EffectManager.start_effect(
        %{
          effect_id: effect_id,
          conversation_id: conversation_id,
          class: :llm,
          kind: "generation",
          input: %{content: "please run with failing cancel"},
          policy: %{max_attempts: 1, backoff_ms: 5, timeout_ms: 5_000}
        },
        nil
      )

    assert_receive {:llm_cancellable_stream, %Request{}, execution_ref}
    assert is_pid(execution_ref)
    Process.sleep(50)

    :ok = EffectManager.cancel_conversation(conversation_id, "user_abort", nil)
    assert_receive {:llm_cancellable_cancel_called, :failed, ^execution_ref}

    assert {:ok, recorded} =
             eventually(fn ->
               case Ingest.replay("conv.effect.llm.generation.**", replay_start) do
                 {:ok, events} ->
                   events_for_effect = Enum.filter(events, &(effect_id_for(&1) == effect_id))
                   lifecycles = Enum.map(events_for_effect, &lifecycle_for/1)

                   if "canceled" in lifecycles do
                     {:ok, {:ok, events_for_effect}}
                   else
                     :retry
                   end

                 other ->
                   {:ok, other}
               end
             end)

    assert Enum.count(recorded, &(lifecycle_for(&1) == "started")) == 1
    assert Enum.count(recorded, &(lifecycle_for(&1) == "canceled")) == 1
    refute Enum.any?(recorded, &(lifecycle_for(&1) == "completed"))
    refute Enum.any?(recorded, &(lifecycle_for(&1) == "failed"))

    canceled_event = Enum.find(recorded, &(lifecycle_for(&1) == "canceled"))
    assert canceled_event
    assert data_field(canceled_event, :reason, nil) == "user_abort"
    assert data_field(canceled_event, :backend_cancel, nil) == "failed"
    assert data_field(canceled_event, :backend_cancel_reason, nil) == "cancel failed"
    assert data_field(canceled_event, :backend_cancel_category, nil) == "provider"
    assert data_field(canceled_event, :backend_cancel_retryable?, nil) == true
    assert data_field(canceled_event, :backend, nil) == "jido_ai"
    assert data_field(canceled_event, :provider, nil) == "stub-provider"
    assert data_field(canceled_event, :model, nil) == "stub-model"

    snapshot =
      eventually(fn ->
        llm = Telemetry.snapshot().llm

        if llm.lifecycle_counts.canceled >= baseline.lifecycle_counts.canceled + 1 and
             llm.cancel_latency_ms.count >= baseline.cancel_latency_ms.count + 1 and
             Map.get(llm.cancel_results, "failed", 0) >=
               Map.get(baseline.cancel_results, "failed", 0) + 1 do
          {:ok, llm}
        else
          :retry
        end
      end)

    assert Map.get(snapshot.cancel_results, "failed", 0) >=
             Map.get(baseline.cancel_results, "failed", 0) + 1

    assert backend_lifecycle_count(snapshot.lifecycle_by_backend, "jido_ai", :canceled) >=
             backend_lifecycle_count(baseline.lifecycle_by_backend, "jido_ai", :canceled) + 1

    assert snapshot.retry_by_category == baseline.retry_by_category
  end

  test "cancel_conversation links canceled lifecycle to explicit cause_id when backend cancellation fails" do
    put_runtime_llm_backend!(LLMCancellableBackendStub, self(), true, cancel_scenario: :failed)
    :ok = Telemetry.reset()
    baseline = Telemetry.snapshot().llm

    conversation_id = unique_id("conversation")
    effect_id = unique_id("effect")
    replay_start = DateTime.utc_now() |> DateTime.to_unix()

    assert {:ok, %{signal: cause_signal}} =
             Ingest.ingest(%{
               id: unique_id("cause"),
               type: "conv.audit.policy.decision_recorded",
               source: "/tests/effect-manager",
               subject: conversation_id,
               data: %{audit_id: unique_id("audit"), category: "policy", decision: "allow"},
               extensions: %{contract_major: 1}
             })

    :ok =
      EffectManager.start_effect(
        %{
          effect_id: effect_id,
          conversation_id: conversation_id,
          class: :llm,
          kind: "generation",
          input: %{content: "please run with failed cancel and explicit cause"},
          policy: %{max_attempts: 1, backoff_ms: 5, timeout_ms: 5_000}
        },
        nil
      )

    assert_receive {:llm_cancellable_stream, %Request{}, execution_ref}
    assert is_pid(execution_ref)
    Process.sleep(50)

    :ok = EffectManager.cancel_conversation(conversation_id, "user_abort", cause_signal.id)
    assert_receive {:llm_cancellable_cancel_called, :failed, ^execution_ref}

    canceled_events =
      eventually(fn ->
        case Ingest.replay("conv.effect.llm.generation.canceled", replay_start) do
          {:ok, events} ->
            matches = Enum.filter(events, &(effect_id_for(&1) == effect_id))
            if matches == [], do: :retry, else: {:ok, matches}

          _other ->
            :retry
        end
      end)

    assert Enum.count(canceled_events, &(lifecycle_for(&1) == "canceled")) == 1
    canceled_event = Enum.find(canceled_events, &(lifecycle_for(&1) == "canceled"))
    assert canceled_event
    assert data_field(canceled_event, :reason, nil) == "user_abort"
    assert data_field(canceled_event, :backend_cancel, nil) == "failed"
    assert data_field(canceled_event, :backend_cancel_reason, nil) == "cancel failed"
    assert data_field(canceled_event, :backend_cancel_category, nil) == "provider"
    assert data_field(canceled_event, :backend_cancel_retryable?, nil) == true
    assert data_field(canceled_event, :backend, nil) == "jido_ai"
    assert data_field(canceled_event, :provider, nil) == "stub-provider"
    assert data_field(canceled_event, :model, nil) == "stub-model"

    trace = Ingest.trace_chain(canceled_event.signal.id, :backward)
    trace_ids = Enum.map(trace, & &1.id)

    assert canceled_event.signal.id in trace_ids
    assert cause_signal.id in trace_ids
    assert_terminal_canceled_only!(effect_id, replay_start)

    snapshot =
      eventually(fn ->
        llm = Telemetry.snapshot().llm

        if llm.lifecycle_counts.canceled >= baseline.lifecycle_counts.canceled + 1 and
             llm.cancel_latency_ms.count >= baseline.cancel_latency_ms.count + 1 and
             Map.get(llm.cancel_results, "failed", 0) >=
               Map.get(baseline.cancel_results, "failed", 0) + 1 do
          {:ok, llm}
        else
          :retry
        end
      end)

    assert Map.get(snapshot.cancel_results, "failed", 0) >=
             Map.get(baseline.cancel_results, "failed", 0) + 1

    assert backend_lifecycle_count(snapshot.lifecycle_by_backend, "jido_ai", :canceled) >=
             backend_lifecycle_count(baseline.lifecycle_by_backend, "jido_ai", :canceled) + 1

    assert snapshot.retry_by_category == baseline.retry_by_category
  end

  test "cancel_conversation falls back to uncoupled canceled lifecycle when cause_id is invalid and backend cancel fails (legacy path)" do
    put_runtime_llm_backend!(LLMCancellableBackendStub, self(), true, cancel_scenario: :failed)
    :ok = Telemetry.reset()
    baseline = Telemetry.snapshot().llm

    conversation_id = unique_id("conversation")
    effect_id = unique_id("effect")
    replay_start = DateTime.utc_now() |> DateTime.to_unix()
    invalid_cause_id = unique_id("unknown-cause")

    :ok =
      EffectManager.start_effect(
        %{
          effect_id: effect_id,
          conversation_id: conversation_id,
          class: :llm,
          kind: "generation",
          input: %{content: "please run with failed cancel and invalid cause"},
          policy: %{max_attempts: 1, backoff_ms: 5, timeout_ms: 5_000}
        },
        nil
      )

    assert_receive {:llm_cancellable_stream, %Request{}, execution_ref}
    assert is_pid(execution_ref)
    Process.sleep(50)

    :ok = EffectManager.cancel_conversation(conversation_id, "user_abort", invalid_cause_id)
    assert_receive {:llm_cancellable_cancel_called, :failed, ^execution_ref}

    canceled_events =
      eventually(fn ->
        case Ingest.replay("conv.effect.llm.generation.canceled", replay_start) do
          {:ok, events} ->
            matches = Enum.filter(events, &(effect_id_for(&1) == effect_id))
            if matches == [], do: :retry, else: {:ok, matches}

          _other ->
            :retry
        end
      end)

    assert Enum.count(canceled_events, &(lifecycle_for(&1) == "canceled")) == 1
    canceled_event = Enum.find(canceled_events, &(lifecycle_for(&1) == "canceled"))
    assert canceled_event
    assert data_field(canceled_event, :reason, nil) == "user_abort"
    assert data_field(canceled_event, :backend_cancel, nil) == "failed"
    assert data_field(canceled_event, :backend_cancel_reason, nil) == "cancel failed"
    assert data_field(canceled_event, :backend_cancel_category, nil) == "provider"
    assert data_field(canceled_event, :backend_cancel_retryable?, nil) == true
    assert data_field(canceled_event, :backend, nil) == "jido_ai"
    assert data_field(canceled_event, :provider, nil) == "stub-provider"
    assert data_field(canceled_event, :model, nil) == "stub-model"

    trace = Ingest.trace_chain(canceled_event.signal.id, :backward)
    trace_ids = Enum.map(trace, & &1.id)

    assert canceled_event.signal.id in trace_ids
    refute invalid_cause_id in trace_ids
    assert_terminal_canceled_only!(effect_id, replay_start)

    snapshot =
      eventually(fn ->
        llm = Telemetry.snapshot().llm

        if llm.lifecycle_counts.canceled >= baseline.lifecycle_counts.canceled + 1 and
             llm.cancel_latency_ms.count >= baseline.cancel_latency_ms.count + 1 and
             Map.get(llm.cancel_results, "failed", 0) >=
               Map.get(baseline.cancel_results, "failed", 0) + 1 do
          {:ok, llm}
        else
          :retry
        end
      end)

    assert Map.get(snapshot.cancel_results, "failed", 0) >=
             Map.get(baseline.cancel_results, "failed", 0) + 1

    assert backend_lifecycle_count(snapshot.lifecycle_by_backend, "jido_ai", :canceled) >=
             backend_lifecycle_count(baseline.lifecycle_by_backend, "jido_ai", :canceled) + 1

    assert snapshot.retry_by_category == baseline.retry_by_category
  end

  test "cancel_conversation links canceled lifecycle to explicit cause_id when provided" do
    put_runtime_llm_backend!(LLMCancellableBackendStub, self())
    :ok = Telemetry.reset()
    baseline = Telemetry.snapshot().llm

    conversation_id = unique_id("conversation")
    effect_id = unique_id("effect")
    replay_start = DateTime.utc_now() |> DateTime.to_unix()

    assert {:ok, %{signal: cause_signal}} =
             Ingest.ingest(%{
               id: unique_id("cause"),
               type: "conv.audit.policy.decision_recorded",
               source: "/tests/effect-manager",
               subject: conversation_id,
               data: %{audit_id: unique_id("audit"), category: "policy", decision: "allow"},
               extensions: %{contract_major: 1}
             })

    :ok =
      EffectManager.start_effect(
        %{
          effect_id: effect_id,
          conversation_id: conversation_id,
          class: :llm,
          kind: "generation",
          input: %{content: "please run with explicit cancel cause"},
          policy: %{max_attempts: 1, backoff_ms: 5, timeout_ms: 5_000}
        },
        nil
      )

    assert_receive {:llm_cancellable_stream, %Request{}, execution_ref}
    assert is_pid(execution_ref)
    Process.sleep(50)

    :ok = EffectManager.cancel_conversation(conversation_id, "user_abort", cause_signal.id)
    assert_receive {:llm_cancellable_cancel_called, :ok, ^execution_ref}

    canceled_events =
      eventually(fn ->
        case Ingest.replay("conv.effect.llm.generation.canceled", replay_start) do
          {:ok, events} ->
            matches = Enum.filter(events, &(effect_id_for(&1) == effect_id))
            if matches == [], do: :retry, else: {:ok, matches}

          _other ->
            :retry
        end
      end)

    assert Enum.count(canceled_events, &(lifecycle_for(&1) == "canceled")) == 1
    canceled_event = Enum.find(canceled_events, &(lifecycle_for(&1) == "canceled"))
    assert canceled_event
    assert data_field(canceled_event, :reason, nil) == "user_abort"
    assert data_field(canceled_event, :backend_cancel, nil) == "ok"
    assert data_field(canceled_event, :backend, nil) == "jido_ai"
    assert data_field(canceled_event, :provider, nil) == "stub-provider"
    assert data_field(canceled_event, :model, nil) == "stub-model"

    trace = Ingest.trace_chain(canceled_event.signal.id, :backward)
    trace_ids = Enum.map(trace, & &1.id)

    assert canceled_event.signal.id in trace_ids
    assert cause_signal.id in trace_ids
    assert_terminal_canceled_only!(effect_id, replay_start)

    snapshot =
      eventually(fn ->
        llm = Telemetry.snapshot().llm

        if llm.lifecycle_counts.canceled >= baseline.lifecycle_counts.canceled + 1 and
             llm.cancel_latency_ms.count >= baseline.cancel_latency_ms.count + 1 and
             Map.get(llm.cancel_results, "ok", 0) >=
               Map.get(baseline.cancel_results, "ok", 0) + 1 do
          {:ok, llm}
        else
          :retry
        end
      end)

    assert Map.get(snapshot.cancel_results, "ok", 0) >=
             Map.get(baseline.cancel_results, "ok", 0) + 1

    assert backend_lifecycle_count(snapshot.lifecycle_by_backend, "jido_ai", :canceled) >=
             backend_lifecycle_count(baseline.lifecycle_by_backend, "jido_ai", :canceled) + 1

    assert snapshot.retry_by_category == baseline.retry_by_category
  end

  test "cancel_conversation falls back to uncoupled canceled lifecycle when cause_id is invalid" do
    put_runtime_llm_backend!(LLMCancellableBackendStub, self())
    :ok = Telemetry.reset()
    baseline = Telemetry.snapshot().llm

    conversation_id = unique_id("conversation")
    effect_id = unique_id("effect")
    replay_start = DateTime.utc_now() |> DateTime.to_unix()
    invalid_cause_id = unique_id("unknown-cause")

    :ok =
      EffectManager.start_effect(
        %{
          effect_id: effect_id,
          conversation_id: conversation_id,
          class: :llm,
          kind: "generation",
          input: %{content: "please run with invalid cancel cause"},
          policy: %{max_attempts: 1, backoff_ms: 5, timeout_ms: 5_000}
        },
        nil
      )

    assert_receive {:llm_cancellable_stream, %Request{}, execution_ref}
    assert is_pid(execution_ref)
    Process.sleep(50)

    :ok = EffectManager.cancel_conversation(conversation_id, "user_abort", invalid_cause_id)
    assert_receive {:llm_cancellable_cancel_called, :ok, ^execution_ref}

    canceled_events =
      eventually(fn ->
        case Ingest.replay("conv.effect.llm.generation.canceled", replay_start) do
          {:ok, events} ->
            matches = Enum.filter(events, &(effect_id_for(&1) == effect_id))
            if matches == [], do: :retry, else: {:ok, matches}

          _other ->
            :retry
        end
      end)

    assert Enum.count(canceled_events, &(lifecycle_for(&1) == "canceled")) == 1
    canceled_event = Enum.find(canceled_events, &(lifecycle_for(&1) == "canceled"))
    assert canceled_event
    assert data_field(canceled_event, :reason, nil) == "user_abort"
    assert data_field(canceled_event, :backend_cancel, nil) == "ok"
    assert data_field(canceled_event, :backend, nil) == "jido_ai"
    assert data_field(canceled_event, :provider, nil) == "stub-provider"
    assert data_field(canceled_event, :model, nil) == "stub-model"

    trace = Ingest.trace_chain(canceled_event.signal.id, :backward)
    trace_ids = Enum.map(trace, & &1.id)

    assert canceled_event.signal.id in trace_ids
    refute invalid_cause_id in trace_ids
    assert_terminal_canceled_only!(effect_id, replay_start)

    snapshot =
      eventually(fn ->
        llm = Telemetry.snapshot().llm

        if llm.lifecycle_counts.canceled >= baseline.lifecycle_counts.canceled + 1 and
             llm.cancel_latency_ms.count >= baseline.cancel_latency_ms.count + 1 and
             Map.get(llm.cancel_results, "ok", 0) >=
               Map.get(baseline.cancel_results, "ok", 0) + 1 do
          {:ok, llm}
        else
          :retry
        end
      end)

    assert Map.get(snapshot.cancel_results, "ok", 0) >=
             Map.get(baseline.cancel_results, "ok", 0) + 1

    assert backend_lifecycle_count(snapshot.lifecycle_by_backend, "jido_ai", :canceled) >=
             backend_lifecycle_count(baseline.lifecycle_by_backend, "jido_ai", :canceled) + 1

    assert snapshot.retry_by_category == baseline.retry_by_category
  end

  test "cancel_conversation falls back to uncoupled canceled lifecycle when cause_id is invalid and backend cancel fails" do
    put_runtime_llm_backend!(LLMCancellableBackendStub, self(), true, cancel_scenario: :failed)
    :ok = Telemetry.reset()
    baseline = Telemetry.snapshot().llm

    conversation_id = unique_id("conversation")
    effect_id = unique_id("effect")
    replay_start = DateTime.utc_now() |> DateTime.to_unix()
    invalid_cause_id = unique_id("unknown-cause")

    :ok =
      EffectManager.start_effect(
        %{
          effect_id: effect_id,
          conversation_id: conversation_id,
          class: :llm,
          kind: "generation",
          input: %{content: "please run with invalid cause and failed cancel"},
          policy: %{max_attempts: 1, backoff_ms: 5, timeout_ms: 5_000}
        },
        nil
      )

    assert_receive {:llm_cancellable_stream, %Request{}, execution_ref}
    assert is_pid(execution_ref)
    Process.sleep(50)

    :ok = EffectManager.cancel_conversation(conversation_id, "user_abort", invalid_cause_id)
    assert_receive {:llm_cancellable_cancel_called, :failed, ^execution_ref}

    canceled_events =
      eventually(fn ->
        case Ingest.replay("conv.effect.llm.generation.canceled", replay_start) do
          {:ok, events} ->
            matches = Enum.filter(events, &(effect_id_for(&1) == effect_id))
            if matches == [], do: :retry, else: {:ok, matches}

          _other ->
            :retry
        end
      end)

    assert Enum.count(canceled_events, &(lifecycle_for(&1) == "canceled")) == 1
    canceled_event = Enum.find(canceled_events, &(lifecycle_for(&1) == "canceled"))
    assert canceled_event
    assert data_field(canceled_event, :reason, nil) == "user_abort"
    assert data_field(canceled_event, :backend_cancel, nil) == "failed"
    assert data_field(canceled_event, :backend_cancel_reason, nil) == "cancel failed"

    trace = Ingest.trace_chain(canceled_event.signal.id, :backward)
    trace_ids = Enum.map(trace, & &1.id)

    assert canceled_event.signal.id in trace_ids
    refute invalid_cause_id in trace_ids

    snapshot =
      eventually(fn ->
        llm = Telemetry.snapshot().llm

        if llm.lifecycle_counts.canceled >= baseline.lifecycle_counts.canceled + 1 and
             Map.get(llm.cancel_results, "failed", 0) >=
               Map.get(baseline.cancel_results, "failed", 0) + 1 do
          {:ok, llm}
        else
          :retry
        end
      end)

    assert Map.get(snapshot.cancel_results, "failed", 0) >=
             Map.get(baseline.cancel_results, "failed", 0) + 1

    assert snapshot.retry_by_category == baseline.retry_by_category
  end

  test "invalid cause_id falls back to uncoupled lifecycle ingestion" do
    conversation_id = unique_id("conversation")
    effect_id = unique_id("effect")
    replay_start = DateTime.utc_now() |> DateTime.to_unix()

    :ok =
      EffectManager.start_effect(
        %{
          effect_id: effect_id,
          conversation_id: conversation_id,
          class: :tool,
          kind: "execution",
          input: %{tool_name: "read_file"},
          simulate: %{latency_ms: 5},
          policy: %{max_attempts: 1, backoff_ms: 5, timeout_ms: 120}
        },
        unique_id("unknown-cause")
      )

    assert {:ok, _recorded} =
             eventually(fn ->
               case Ingest.replay("conv.effect.tool.execution.**", replay_start) do
                 {:ok, events} ->
                   lifecycles = effect_lifecycles(events, effect_id)

                   if includes_all?(lifecycles, ["started", "completed"]) do
                     {:ok, {:ok, events}}
                   else
                     :retry
                   end

                 other ->
                   {:ok, other}
               end
             end)
  end

  test "cancel_conversation emits canceled lifecycle and cleans worker state" do
    conversation_id = unique_id("conversation")
    effect_id = unique_id("effect")
    replay_start = DateTime.utc_now() |> DateTime.to_unix()

    :ok =
      EffectManager.start_effect(
        %{
          effect_id: effect_id,
          conversation_id: conversation_id,
          class: :tool,
          kind: "execution",
          input: %{tool_name: "fetch"},
          simulate: %{latency_ms: 500},
          policy: %{max_attempts: 1, backoff_ms: 5, timeout_ms: 1_000}
        },
        nil
      )

    eventually(fn ->
      case Ingest.replay("conv.effect.tool.execution.started", replay_start) do
        {:ok, events} ->
          if Enum.any?(events, &(effect_id_for(&1) == effect_id)) do
            {:ok, :ok}
          else
            :retry
          end

        _ ->
          :retry
      end
    end)

    :ok = EffectManager.cancel_conversation(conversation_id, "user_abort", nil)

    assert {:ok, replayed} =
             eventually(fn ->
               case Ingest.replay("conv.effect.tool.execution.canceled", replay_start) do
                 {:ok, events} ->
                   matches = Enum.filter(events, &(effect_id_for(&1) == effect_id))
                   if matches == [], do: :retry, else: {:ok, {:ok, matches}}

                 other ->
                   {:ok, other}
               end
             end)

    assert Enum.any?(replayed, &(lifecycle_for(&1) == "canceled"))

    eventually(fn ->
      if EffectManager.stats().in_flight_count == 0 do
        {:ok, :ok}
      else
        :retry
      end
    end)
  end

  defp assert_terminal_canceled_only!(effect_id, replay_start) do
    terminal_events =
      eventually(fn ->
        case Ingest.replay("conv.effect.llm.generation.**", replay_start) do
          {:ok, records} ->
            terminal_events_for_effect(records, effect_id)

          _other ->
            :retry
        end
      end)

    assert Enum.count(terminal_events, &(lifecycle_for(&1) == "canceled")) == 1
    refute Enum.any?(terminal_events, &(lifecycle_for(&1) == "completed"))
    refute Enum.any?(terminal_events, &(lifecycle_for(&1) == "failed"))
  end

  defp terminal_events_for_effect(records, effect_id) when is_list(records) do
    records
    |> Enum.filter(fn event ->
      effect_id_for(event) == effect_id and
        lifecycle_for(event) in ["completed", "failed", "canceled"]
    end)
    |> maybe_retry_terminal_events()
  end

  defp maybe_retry_terminal_events(terminal_events) when is_list(terminal_events) do
    if Enum.any?(terminal_events, &(lifecycle_for(&1) == "canceled")) do
      {:ok, terminal_events}
    else
      :retry
    end
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

  defp includes_all?(lifecycle_values, required_values) do
    lifecycle_set = MapSet.new(lifecycle_values)
    required_set = MapSet.new(required_values)
    MapSet.subset?(required_set, lifecycle_set)
  end

  defp effect_lifecycles(events, effect_id) do
    events
    |> Enum.filter(&(effect_id_for(&1) == effect_id))
    |> Enum.map(&lifecycle_for/1)
  end

  defp lifecycle_for(event) do
    data_field(event, :lifecycle, "")
  end

  defp effect_id_for(event) do
    data_field(event, :effect_id, nil)
  end

  defp data_field(event, key, default) do
    data = event.signal.data || %{}

    case Map.fetch(data, key) do
      {:ok, value} ->
        value

      :error ->
        Map.get(data, to_string(key), default)
    end
  end

  defp to_integer(value) when is_integer(value), do: value

  defp to_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      _ -> 0
    end
  end

  defp to_integer(_value), do: 0

  defp backend_lifecycle_count(lifecycle_by_backend, backend, key)
       when is_map(lifecycle_by_backend) and is_binary(backend) and is_atom(key) do
    lifecycle_by_backend
    |> Map.get(backend, %{})
    |> Map.get(key, 0)
  end

  defp unique_id(prefix) do
    "#{prefix}-#{System.unique_integer([:positive, :monotonic])}"
  end

  defp put_runtime_llm_backend!(module, test_pid, stream? \\ true, backend_opts \\ [])
       when is_atom(module) and is_pid(test_pid) and is_boolean(stream?) and is_list(backend_opts) do
    put_runtime_llm_backend_for!(:jido_ai, module, test_pid, stream?, backend_opts)
  end

  defp put_runtime_llm_backend_for!(
         default_backend,
         module,
         test_pid,
         stream? \\ true,
         backend_opts \\ []
       )
       when default_backend in [:jido_ai, :harness] and is_atom(module) and is_pid(test_pid) and
              is_boolean(stream?) and is_list(backend_opts) do
    selected_backend_cfg = [
      module: module,
      stream?: stream?,
      timeout_ms: 1_000,
      provider: "stub-provider",
      model: "stub-model",
      options: [test_pid: test_pid] ++ backend_opts
    ]

    empty_backend_cfg = [module: nil, stream?: stream?, options: []]

    jido_ai_cfg =
      if default_backend == :jido_ai, do: selected_backend_cfg, else: empty_backend_cfg

    harness_cfg =
      if default_backend == :harness, do: selected_backend_cfg, else: empty_backend_cfg

    Application.put_env(@app, @key,
      llm: [
        default_backend: default_backend,
        default_stream?: stream?,
        default_timeout_ms: 1_000,
        default_provider: "stub-provider",
        default_model: "stub-model",
        backends: [
          jido_ai: jido_ai_cfg,
          harness: harness_cfg
        ]
      ]
    )
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
