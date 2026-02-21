defmodule JidoConversation.Runtime.LLMRetryPolicyStreamMatrixTest do
  use ExUnit.Case, async: false

  alias JidoConversation.Ingest
  alias JidoConversation.Runtime.Coordinator
  alias JidoConversation.Runtime.EffectManager
  alias JidoConversation.Runtime.IngressSubscriber

  @app :jido_conversation
  @key JidoConversation.EventSystem

  defmodule RetryStreamJidoAI do
    def resolve_model(:fast), do: "openai:gpt-4o-mini"
    def resolve_model(:capable), do: "openai:gpt-4o"
    def resolve_model(model) when is_binary(model), do: model
    def resolve_model(_), do: "openai:gpt-4o-mini"
  end

  defmodule RetryStreamLLMClient do
    def stream_text(context, model, _messages, _opts) do
      attempt = next_attempt(context.counter)
      send(context.test_pid, {:jido_ai_stream_text, context.scenario, attempt, model})
      {:ok, %{attempt: attempt}}
    end

    def process_stream(context, %{attempt: attempt}, opts) do
      on_result = Keyword.get(opts, :on_result)

      case context.scenario do
        :non_retryable_422 ->
          {:error, %{status: 422, message: "unprocessable_entity"}}

        :retryable_then_success ->
          process_retryable_stream_attempt(attempt, on_result)
      end
    end

    def generate_text(_context, model, _messages, _opts) do
      {:ok, %{model: model, message: %{content: "fallback"}}}
    end

    defp next_attempt(counter) when is_pid(counter) do
      Agent.get_and_update(counter, fn value ->
        next = value + 1
        {next, next}
      end)
    end

    defp process_retryable_stream_attempt(1, _on_result) do
      {:error, %{status: 503, message: "service_unavailable"}}
    end

    defp process_retryable_stream_attempt(_attempt, on_result) do
      if is_function(on_result, 1), do: on_result.("stream-ok")

      {:ok,
       %{
         model: "openai:gpt-4o-mini",
         finish_reason: :stop,
         message: %{content: "stream-ok"},
         usage: %{input_tokens: 2, output_tokens: 3}
       }}
    end
  end

  defmodule RetryStreamHarness do
    def run(provider, prompt, opts)
        when is_atom(provider) and is_binary(prompt) and is_list(opts) do
      scenario = Keyword.fetch!(opts, :scenario)
      counter = Keyword.fetch!(opts, :counter)
      test_pid = Keyword.get(opts, :test_pid, self())
      attempt = next_attempt(counter)

      send(test_pid, {:harness_stream_run, scenario, attempt, provider})

      case scenario do
        :non_retryable_422 ->
          {:ok,
           [
             %{type: :session_started, provider: provider, payload: %{}},
             %{
               type: :session_failed,
               payload: %{
                 "error" => %{"status" => 422, "message" => "invalid_request"}
               }
             }
           ]}

        :retryable_then_success ->
          if attempt == 1 do
            {:ok,
             [
               %{type: :session_started, provider: provider, payload: %{}},
               %{
                 type: :session_failed,
                 payload: %{
                   "error" => %{"status" => 503, "message" => "upstream_unavailable"}
                 }
               }
             ]}
          else
            {:ok,
             [
               %{type: :session_started, provider: provider, payload: %{}},
               %{type: :output_text_delta, payload: %{"text" => "stream"}},
               %{
                 type: :session_completed,
                 payload: %{
                   "output_text" => "stream harness ok",
                   "usage" => %{"input_tokens" => 1, "output_tokens" => 2}
                 }
               }
             ]}
          end
      end
    end

    def run(prompt, opts) when is_binary(prompt) and is_list(opts) do
      run(:codex, prompt, opts)
    end

    def cancel(_provider, _session_id), do: :ok

    defp next_attempt(counter) when is_pid(counter) do
      Agent.get_and_update(counter, fn value ->
        next = value + 1
        {next, next}
      end)
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

  test "jido_ai stream 4xx provider errors are non-retryable at runtime" do
    counter = start_counter!()
    put_runtime_backend!(:jido_ai, llm_client_context(:non_retryable_422, counter))

    conversation_id = unique_id("conversation-jido-ai-stream-non-retryable")
    effect_id = unique_id("effect-jido-ai-stream-non-retryable")
    replay_start = DateTime.utc_now() |> DateTime.to_unix()

    :ok =
      EffectManager.start_effect(
        %{
          effect_id: effect_id,
          conversation_id: conversation_id,
          class: :llm,
          kind: "generation",
          input: %{content: "trigger stream non-retryable"},
          policy: %{max_attempts: 3, backoff_ms: 5, timeout_ms: 800}
        },
        nil
      )

    assert_receive {:jido_ai_stream_text, :non_retryable_422, 1, _model}
    refute_receive {:jido_ai_stream_text, :non_retryable_422, 2, _model}, 200

    events =
      eventually(fn ->
        case Ingest.replay("conv.effect.llm.generation.**", replay_start) do
          {:ok, records} ->
            matches = Enum.filter(records, &(effect_id_for(&1) == effect_id))
            lifecycles = Enum.map(matches, &lifecycle_for/1) |> MapSet.new()

            if MapSet.subset?(MapSet.new(["started", "failed"]), lifecycles) do
              {:ok, matches}
            else
              :retry
            end

          _other ->
            :retry
        end
      end)

    assert Enum.count(events, &(lifecycle_for(&1) == "started")) == 1
    assert Enum.count(events, &(lifecycle_for(&1) == "failed")) == 1

    refute Enum.any?(events, fn event ->
             lifecycle_for(event) == "progress" and data_field(event, :status, nil) == "retrying"
           end)

    assert Agent.get(counter, & &1) == 1
  end

  test "jido_ai stream transient provider failures retry and complete" do
    counter = start_counter!()
    put_runtime_backend!(:jido_ai, llm_client_context(:retryable_then_success, counter))

    conversation_id = unique_id("conversation-jido-ai-stream-retryable")
    effect_id = unique_id("effect-jido-ai-stream-retryable")
    replay_start = DateTime.utc_now() |> DateTime.to_unix()

    :ok =
      EffectManager.start_effect(
        %{
          effect_id: effect_id,
          conversation_id: conversation_id,
          class: :llm,
          kind: "generation",
          input: %{content: "trigger stream retry then success"},
          policy: %{max_attempts: 3, backoff_ms: 5, timeout_ms: 800}
        },
        nil
      )

    assert_receive {:jido_ai_stream_text, :retryable_then_success, 1, _model}
    assert_receive {:jido_ai_stream_text, :retryable_then_success, 2, _model}

    events =
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

    assert Enum.any?(events, fn event ->
             lifecycle_for(event) == "progress" and data_field(event, :status, nil) == "retrying"
           end)

    assert Enum.any?(events, fn event ->
             lifecycle_for(event) == "completed" and
               get_in(data_field(event, :result, %{}), [:text]) == "stream-ok"
           end)

    assert Agent.get(counter, & &1) == 2
  end

  test "harness stream 4xx provider errors are non-retryable at runtime" do
    counter = start_counter!()
    put_runtime_backend!(:harness, %{})

    conversation_id = unique_id("conversation-harness-stream-non-retryable")
    effect_id = unique_id("effect-harness-stream-non-retryable")
    replay_start = DateTime.utc_now() |> DateTime.to_unix()

    :ok =
      EffectManager.start_effect(
        %{
          effect_id: effect_id,
          conversation_id: conversation_id,
          class: :llm,
          kind: "generation",
          input: %{
            content: "trigger harness stream non-retryable",
            request_options: %{
              scenario: :non_retryable_422,
              counter: counter,
              test_pid: self()
            }
          },
          policy: %{max_attempts: 3, backoff_ms: 5, timeout_ms: 800}
        },
        nil
      )

    assert_receive {:harness_stream_run, :non_retryable_422, 1, :codex}
    refute_receive {:harness_stream_run, :non_retryable_422, 2, :codex}, 200

    events =
      eventually(fn ->
        case Ingest.replay("conv.effect.llm.generation.**", replay_start) do
          {:ok, records} ->
            matches = Enum.filter(records, &(effect_id_for(&1) == effect_id))
            lifecycles = Enum.map(matches, &lifecycle_for/1) |> MapSet.new()

            if MapSet.subset?(MapSet.new(["started", "failed"]), lifecycles) do
              {:ok, matches}
            else
              :retry
            end

          _other ->
            :retry
        end
      end)

    assert Enum.count(events, &(lifecycle_for(&1) == "started")) == 1
    assert Enum.count(events, &(lifecycle_for(&1) == "failed")) == 1

    refute Enum.any?(events, fn event ->
             lifecycle_for(event) == "progress" and data_field(event, :status, nil) == "retrying"
           end)

    assert Agent.get(counter, & &1) == 1
  end

  test "harness stream transient provider failures retry and complete" do
    counter = start_counter!()
    put_runtime_backend!(:harness, %{})

    conversation_id = unique_id("conversation-harness-stream-retryable")
    effect_id = unique_id("effect-harness-stream-retryable")
    replay_start = DateTime.utc_now() |> DateTime.to_unix()

    :ok =
      EffectManager.start_effect(
        %{
          effect_id: effect_id,
          conversation_id: conversation_id,
          class: :llm,
          kind: "generation",
          input: %{
            content: "trigger harness stream retry then success",
            request_options: %{
              scenario: :retryable_then_success,
              counter: counter,
              test_pid: self()
            }
          },
          policy: %{max_attempts: 3, backoff_ms: 5, timeout_ms: 800}
        },
        nil
      )

    assert_receive {:harness_stream_run, :retryable_then_success, 1, :codex}
    assert_receive {:harness_stream_run, :retryable_then_success, 2, :codex}

    events =
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

    assert Enum.any?(events, fn event ->
             lifecycle_for(event) == "progress" and data_field(event, :status, nil) == "retrying"
           end)

    assert Enum.any?(events, fn event ->
             lifecycle_for(event) == "completed" and
               get_in(data_field(event, :result, %{}), [:text]) == "stream harness ok"
           end)

    assert Agent.get(counter, & &1) == 2
  end

  defp put_runtime_backend!(:jido_ai, llm_client_context) when is_map(llm_client_context) do
    Application.put_env(@app, @key,
      llm: [
        default_backend: :jido_ai,
        default_stream?: true,
        default_timeout_ms: 800,
        default_provider: "openai",
        default_model: "openai:gpt-4o-mini",
        backends: [
          jido_ai: [
            module: JidoConversation.LLM.Adapters.JidoAI,
            stream?: true,
            timeout_ms: 800,
            provider: "openai",
            model: "openai:gpt-4o-mini",
            options: [
              llm_client_module: RetryStreamLLMClient,
              jido_ai_module: RetryStreamJidoAI,
              llm_client_context: llm_client_context
            ]
          ],
          harness: [
            module: nil,
            stream?: true,
            timeout_ms: 800,
            provider: nil,
            model: nil,
            options: []
          ]
        ]
      ]
    )
  end

  defp put_runtime_backend!(:harness, _opts) do
    Application.put_env(@app, @key,
      llm: [
        default_backend: :harness,
        default_stream?: true,
        default_timeout_ms: 800,
        default_provider: nil,
        default_model: nil,
        backends: [
          jido_ai: [
            module: nil,
            stream?: true,
            timeout_ms: 800,
            provider: nil,
            model: nil,
            options: []
          ],
          harness: [
            module: JidoConversation.LLM.Adapters.Harness,
            stream?: true,
            timeout_ms: 800,
            provider: "codex",
            model: nil,
            options: [
              harness_module: RetryStreamHarness,
              harness_provider: :codex
            ]
          ]
        ]
      ]
    )
  end

  defp llm_client_context(scenario, counter)
       when scenario in [:non_retryable_422, :retryable_then_success] and is_pid(counter) do
    %{scenario: scenario, counter: counter, test_pid: self()}
  end

  defp start_counter! do
    {:ok, counter} = Agent.start_link(fn -> 0 end)
    counter
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
