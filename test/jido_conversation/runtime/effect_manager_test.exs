defmodule JidoConversation.Runtime.EffectManagerTest do
  use ExUnit.Case, async: false

  alias JidoConversation.Ingest
  alias JidoConversation.LLM.Event
  alias JidoConversation.LLM.Request
  alias JidoConversation.LLM.Result
  alias JidoConversation.Runtime.Coordinator
  alias JidoConversation.Runtime.EffectManager
  alias JidoConversation.Runtime.IngressSubscriber

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
      execution_ref = self()
      send(test_pid, {:llm_cancellable_stream, request, execution_ref})

      _ =
        emit.(
          Event.new!(%{
            request_id: request.request_id,
            conversation_id: request.conversation_id,
            backend: request.backend,
            lifecycle: :started,
            provider: "stub-provider",
            model: "stub-model",
            metadata: %{execution_ref: execution_ref}
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
      send(Keyword.get(opts, :test_pid, self()), {:llm_cancellable_cancel_called, execution_ref})
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

  test "non-retryable llm backend errors do not retry even when max_attempts is greater than one" do
    put_runtime_llm_backend!(LLMNonRetryableBackendStub, self())

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

    assert Enum.any?(recorded, fn event ->
             lifecycle_for(event) == "failed" and data_field(event, :retryable?, true) == false
           end)
  end

  test "cancel_conversation triggers llm backend cancel when execution_ref is available" do
    put_runtime_llm_backend!(LLMCancellableBackendStub, self())

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

    assert_receive {:llm_cancellable_stream, %Request{}, _execution_ref}
    Process.sleep(50)

    :ok = EffectManager.cancel_conversation(conversation_id, "user_abort", nil)
    assert_receive {:llm_cancellable_cancel_called, _execution_ref}

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

    assert Enum.any?(recorded, &(lifecycle_for(&1) == "canceled"))

    refute Enum.any?(recorded, &(lifecycle_for(&1) == "completed"))
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

  defp unique_id(prefix) do
    "#{prefix}-#{System.unique_integer([:positive, :monotonic])}"
  end

  defp put_runtime_llm_backend!(module, test_pid) when is_atom(module) and is_pid(test_pid) do
    Application.put_env(@app, @key,
      llm: [
        default_backend: :jido_ai,
        default_stream?: true,
        default_timeout_ms: 1_000,
        default_provider: "stub-provider",
        default_model: "stub-model",
        backends: [
          jido_ai: [
            module: module,
            stream?: true,
            timeout_ms: 1_000,
            provider: "stub-provider",
            model: "stub-model",
            options: [test_pid: test_pid]
          ],
          harness: [module: nil, stream?: true, options: []]
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
