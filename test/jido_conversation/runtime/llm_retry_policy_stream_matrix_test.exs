defmodule JidoConversation.Runtime.LLMRetryPolicyStreamMatrixTest do
  use ExUnit.Case, async: false

  alias JidoConversation.Ingest
  alias JidoConversation.Runtime.Coordinator
  alias JidoConversation.Runtime.EffectManager
  alias JidoConversation.Runtime.IngressSubscriber
  alias JidoConversation.Telemetry

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

        :auth_401 ->
          {:error, %{status: 401, message: "unauthorized"}}

        :unknown_error ->
          {:error, %{message: "unexpected_stream_failure"}}

        :retryable_then_success ->
          scenario_recovery_result(attempt, on_result, :provider, "stream-ok")

        :timeout_then_success ->
          scenario_recovery_result(
            attempt,
            on_result,
            :timeout,
            "stream jido_ai timeout recovered"
          )

        :transport_then_success ->
          scenario_recovery_result(
            attempt,
            on_result,
            :transport,
            "stream jido_ai transport recovered"
          )
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

    defp scenario_recovery_result(1, _on_result, :provider, _content) do
      {:error, %{status: 503, message: "service_unavailable"}}
    end

    defp scenario_recovery_result(1, _on_result, :timeout, _content) do
      {:error, %{reason: :timeout, message: "request_timeout"}}
    end

    defp scenario_recovery_result(1, _on_result, :transport, _content) do
      {:error, %{reason: :econnrefused, message: "network_down"}}
    end

    defp scenario_recovery_result(_attempt, on_result, _kind, content) do
      if is_function(on_result, 1), do: on_result.(content)

      {:ok,
       %{
         model: "openai:gpt-4o-mini",
         finish_reason: :stop,
         message: %{content: content},
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

        :auth_403 ->
          {:ok,
           [
             %{type: :session_started, provider: provider, payload: %{}},
             %{
               type: :session_failed,
               payload: %{
                 "error" => %{"status" => 403, "message" => "forbidden"}
               }
             }
           ]}

        :unknown_error ->
          {:ok,
           [
             %{type: :session_started, provider: provider, payload: %{}},
             %{
               type: :session_failed,
               payload: %{
                 "error" => %{"message" => "harness_stream_unexpected_failure"}
               }
             }
           ]}

        :retryable_then_success ->
          stream_result_for_recovery(attempt, provider, :provider, "stream harness ok")

        :timeout_then_success ->
          stream_result_for_recovery(
            attempt,
            provider,
            :timeout,
            "stream harness timeout recovered"
          )

        :transport_then_success ->
          stream_result_for_recovery(
            attempt,
            provider,
            :transport,
            "stream harness transport recovered"
          )
      end
    end

    def run(prompt, opts) when is_binary(prompt) and is_list(opts) do
      run(:codex, prompt, opts)
    end

    def cancel(_provider, _session_id), do: :ok

    defp stream_result_for_recovery(1, provider, :provider, _text) do
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
    end

    defp stream_result_for_recovery(1, provider, :timeout, _text) do
      {:ok,
       [
         %{type: :session_started, provider: provider, payload: %{}},
         %{
           type: :session_failed,
           payload: %{
             "error" => %{"reason" => :timeout, "message" => "request_timeout"}
           }
         }
       ]}
    end

    defp stream_result_for_recovery(1, provider, :transport, _text) do
      {:ok,
       [
         %{type: :session_started, provider: provider, payload: %{}},
         %{
           type: :session_failed,
           payload: %{
             "error" => %{"reason" => :econnrefused, "message" => "network_down"}
           }
         }
       ]}
    end

    defp stream_result_for_recovery(_attempt, provider, _kind, text) do
      {:ok,
       [
         %{type: :session_started, provider: provider, payload: %{}},
         %{type: :output_text_delta, payload: %{"text" => "stream"}},
         %{
           type: :session_completed,
           payload: %{
             "output_text" => text,
             "usage" => %{"input_tokens" => 1, "output_tokens" => 2}
           }
         }
       ]}
    end

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
    :ok = Telemetry.reset()
    baseline = Telemetry.snapshot().llm

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

    snapshot =
      eventually(fn ->
        llm = Telemetry.snapshot().llm

        if llm.lifecycle_counts.failed >= baseline.lifecycle_counts.failed + 1 do
          {:ok, llm}
        else
          :retry
        end
      end)

    assert llm_retry_count(snapshot.retry_by_category, "provider") ==
             llm_retry_count(baseline.retry_by_category, "provider")
  end

  test "jido_ai stream transient provider failures retry and complete" do
    counter = start_counter!()
    put_runtime_backend!(:jido_ai, llm_client_context(:retryable_then_success, counter))
    :ok = Telemetry.reset()
    baseline = Telemetry.snapshot().llm

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

    snapshot =
      eventually(fn ->
        llm = Telemetry.snapshot().llm
        retries = llm_retry_count(llm.retry_by_category, "provider")

        if llm.lifecycle_counts.completed >= baseline.lifecycle_counts.completed + 1 and
             retries >= llm_retry_count(baseline.retry_by_category, "provider") + 1 do
          {:ok, llm}
        else
          :retry
        end
      end)

    assert llm_retry_count(snapshot.retry_by_category, "provider") >=
             llm_retry_count(baseline.retry_by_category, "provider") + 1
  end

  test "jido_ai stream auth failures are non-retryable and emit auth category at runtime" do
    counter = start_counter!()
    put_runtime_backend!(:jido_ai, llm_client_context(:auth_401, counter))
    baseline = reset_llm_baseline!()
    conversation_id = unique_id("conversation-jido-ai-stream-auth-non-retryable")
    effect_id = unique_id("effect-jido-ai-stream-auth-non-retryable")
    replay_start = DateTime.utc_now() |> DateTime.to_unix()

    start_retry_category_effect!(effect_id, conversation_id)

    assert_receive {:jido_ai_stream_text, :auth_401, 1, _model}
    refute_receive {:jido_ai_stream_text, :auth_401, 2, _model}, 200

    events = await_failed_llm_effect_events(effect_id, replay_start)
    assert_non_retryable_failed_path!(events, "auth")
    assert Agent.get(counter, & &1) == 1

    assert_non_retryable_category_telemetry_unchanged!(baseline, "auth")
  end

  test "jido_ai stream unknown failures are non-retryable and emit unknown category at runtime" do
    counter = start_counter!()
    put_runtime_backend!(:jido_ai, llm_client_context(:unknown_error, counter))
    baseline = reset_llm_baseline!()
    conversation_id = unique_id("conversation-jido-ai-stream-unknown-non-retryable")
    effect_id = unique_id("effect-jido-ai-stream-unknown-non-retryable")
    replay_start = DateTime.utc_now() |> DateTime.to_unix()

    start_retry_category_effect!(effect_id, conversation_id)

    assert_receive {:jido_ai_stream_text, :unknown_error, 1, _model}
    refute_receive {:jido_ai_stream_text, :unknown_error, 2, _model}, 200

    events = await_failed_llm_effect_events(effect_id, replay_start)
    assert_non_retryable_failed_path!(events, "unknown")
    assert Agent.get(counter, & &1) == 1

    assert_non_retryable_category_telemetry_unchanged!(baseline, "unknown")
  end

  test "harness stream 4xx provider errors are non-retryable at runtime" do
    counter = start_counter!()
    put_runtime_backend!(:harness, %{})
    :ok = Telemetry.reset()
    baseline = Telemetry.snapshot().llm

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

    snapshot =
      eventually(fn ->
        llm = Telemetry.snapshot().llm

        if llm.lifecycle_counts.failed >= baseline.lifecycle_counts.failed + 1 do
          {:ok, llm}
        else
          :retry
        end
      end)

    assert llm_retry_count(snapshot.retry_by_category, "provider") ==
             llm_retry_count(baseline.retry_by_category, "provider")
  end

  test "harness stream transient provider failures retry and complete" do
    counter = start_counter!()
    put_runtime_backend!(:harness, %{})
    :ok = Telemetry.reset()
    baseline = Telemetry.snapshot().llm

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

    snapshot =
      eventually(fn ->
        llm = Telemetry.snapshot().llm
        retries = llm_retry_count(llm.retry_by_category, "provider")

        if llm.lifecycle_counts.completed >= baseline.lifecycle_counts.completed + 1 and
             retries >= llm_retry_count(baseline.retry_by_category, "provider") + 1 do
          {:ok, llm}
        else
          :retry
        end
      end)

    assert llm_retry_count(snapshot.retry_by_category, "provider") >=
             llm_retry_count(baseline.retry_by_category, "provider") + 1
  end

  test "harness stream auth failures are non-retryable and emit auth category at runtime" do
    counter = start_counter!()
    put_runtime_backend!(:harness, %{})
    baseline = reset_llm_baseline!()
    conversation_id = unique_id("conversation-harness-stream-auth-non-retryable")
    effect_id = unique_id("effect-harness-stream-auth-non-retryable")
    replay_start = DateTime.utc_now() |> DateTime.to_unix()

    start_retry_category_effect!(
      effect_id,
      conversation_id,
      %{request_options: %{scenario: :auth_403, counter: counter, test_pid: self()}}
    )

    assert_receive {:harness_stream_run, :auth_403, 1, :codex}
    refute_receive {:harness_stream_run, :auth_403, 2, :codex}, 200

    events = await_failed_llm_effect_events(effect_id, replay_start)
    assert_non_retryable_failed_path!(events, "auth")
    assert Agent.get(counter, & &1) == 1

    assert_non_retryable_category_telemetry_unchanged!(baseline, "auth")
  end

  test "harness stream unknown failures are non-retryable and emit unknown category at runtime" do
    counter = start_counter!()
    put_runtime_backend!(:harness, %{})
    baseline = reset_llm_baseline!()
    conversation_id = unique_id("conversation-harness-stream-unknown-non-retryable")
    effect_id = unique_id("effect-harness-stream-unknown-non-retryable")
    replay_start = DateTime.utc_now() |> DateTime.to_unix()

    start_retry_category_effect!(
      effect_id,
      conversation_id,
      %{request_options: %{scenario: :unknown_error, counter: counter, test_pid: self()}}
    )

    assert_receive {:harness_stream_run, :unknown_error, 1, :codex}
    refute_receive {:harness_stream_run, :unknown_error, 2, :codex}, 200

    events = await_failed_llm_effect_events(effect_id, replay_start)
    assert_non_retryable_failed_path!(events, "unknown")
    assert Agent.get(counter, & &1) == 1

    assert_non_retryable_category_telemetry_unchanged!(baseline, "unknown")
  end

  test "jido_ai stream timeout failures retry and increment timeout retry telemetry category" do
    assert_retry_category_recovery_jido_ai(
      :timeout_then_success,
      "timeout",
      "stream jido_ai timeout recovered"
    )
  end

  test "jido_ai stream transport failures retry and increment transport retry telemetry category" do
    assert_retry_category_recovery_jido_ai(
      :transport_then_success,
      "transport",
      "stream jido_ai transport recovered"
    )
  end

  test "harness stream timeout failures retry and increment timeout retry telemetry category" do
    assert_retry_category_recovery_harness(
      :timeout_then_success,
      "timeout",
      "stream harness timeout recovered"
    )
  end

  test "harness stream transport failures retry and increment transport retry telemetry category" do
    assert_retry_category_recovery_harness(
      :transport_then_success,
      "transport",
      "stream harness transport recovered"
    )
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
       when scenario in [
              :non_retryable_422,
              :auth_401,
              :unknown_error,
              :retryable_then_success,
              :timeout_then_success,
              :transport_then_success
            ] and is_pid(counter) do
    %{scenario: scenario, counter: counter, test_pid: self()}
  end

  defp assert_retry_category_recovery_jido_ai(scenario, expected_category, expected_text)
       when is_atom(scenario) and is_binary(expected_category) and is_binary(expected_text) do
    counter = start_counter!()
    put_runtime_backend!(:jido_ai, llm_client_context(scenario, counter))
    baseline = reset_llm_baseline!()
    conversation_id = unique_id("conversation-jido-ai-stream-#{scenario}")
    effect_id = unique_id("effect-jido-ai-stream-#{scenario}")
    replay_start = DateTime.utc_now() |> DateTime.to_unix()

    start_retry_category_effect!(effect_id, conversation_id)

    assert_receive {:jido_ai_stream_text, ^scenario, 1, _model}
    assert_receive {:jido_ai_stream_text, ^scenario, 2, _model}

    events = await_completed_llm_effect_events(effect_id, replay_start)
    assert_retrying_progress_and_completed_text!(events, expected_text)
    assert Agent.get(counter, & &1) == 2

    assert_retry_category_telemetry_increment!(baseline, expected_category)
  end

  defp assert_retry_category_recovery_harness(scenario, expected_category, expected_text)
       when is_atom(scenario) and is_binary(expected_category) and is_binary(expected_text) do
    counter = start_counter!()
    put_runtime_backend!(:harness, %{})
    baseline = reset_llm_baseline!()
    conversation_id = unique_id("conversation-harness-stream-#{scenario}")
    effect_id = unique_id("effect-harness-stream-#{scenario}")
    replay_start = DateTime.utc_now() |> DateTime.to_unix()

    start_retry_category_effect!(
      effect_id,
      conversation_id,
      %{request_options: %{scenario: scenario, counter: counter, test_pid: self()}}
    )

    assert_receive {:harness_stream_run, ^scenario, 1, :codex}
    assert_receive {:harness_stream_run, ^scenario, 2, :codex}

    events = await_completed_llm_effect_events(effect_id, replay_start)
    assert_retrying_progress_and_completed_text!(events, expected_text)
    assert Agent.get(counter, & &1) == 2

    assert_retry_category_telemetry_increment!(baseline, expected_category)
  end

  defp reset_llm_baseline! do
    :ok = Telemetry.reset()
    Telemetry.snapshot().llm
  end

  defp start_retry_category_effect!(effect_id, conversation_id, input_overrides \\ %{})
       when is_binary(effect_id) and is_binary(conversation_id) and is_map(input_overrides) do
    input =
      %{
        content: "stream retry category path"
      }
      |> Map.merge(input_overrides)

    :ok =
      EffectManager.start_effect(
        %{
          effect_id: effect_id,
          conversation_id: conversation_id,
          class: :llm,
          kind: "generation",
          input: input,
          policy: %{max_attempts: 3, backoff_ms: 5, timeout_ms: 800}
        },
        nil
      )
  end

  defp await_completed_llm_effect_events(effect_id, replay_start) do
    eventually(fn -> completed_llm_effect_events(effect_id, replay_start) end)
  end

  defp await_failed_llm_effect_events(effect_id, replay_start) do
    eventually(fn -> failed_llm_effect_events(effect_id, replay_start) end)
  end

  defp completed_llm_effect_events(effect_id, replay_start) do
    case Ingest.replay("conv.effect.llm.generation.**", replay_start) do
      {:ok, records} ->
        matches = Enum.filter(records, &(effect_id_for(&1) == effect_id))

        if completed_lifecycle_set?(matches) do
          {:ok, matches}
        else
          :retry
        end

      _other ->
        :retry
    end
  end

  defp failed_llm_effect_events(effect_id, replay_start) do
    case Ingest.replay("conv.effect.llm.generation.**", replay_start) do
      {:ok, records} ->
        matches = Enum.filter(records, &(effect_id_for(&1) == effect_id))

        if failed_lifecycle_set?(matches) do
          {:ok, matches}
        else
          :retry
        end

      _other ->
        :retry
    end
  end

  defp completed_lifecycle_set?(matches) when is_list(matches) do
    lifecycles = Enum.map(matches, &lifecycle_for/1) |> MapSet.new()
    MapSet.subset?(MapSet.new(["started", "progress", "completed"]), lifecycles)
  end

  defp failed_lifecycle_set?(matches) when is_list(matches) do
    lifecycles = Enum.map(matches, &lifecycle_for/1) |> MapSet.new()
    MapSet.subset?(MapSet.new(["started", "failed"]), lifecycles)
  end

  defp assert_retrying_progress_and_completed_text!(events, expected_text)
       when is_list(events) and is_binary(expected_text) do
    assert Enum.any?(events, fn event ->
             lifecycle_for(event) == "progress" and data_field(event, :status, nil) == "retrying"
           end)

    assert Enum.any?(events, fn event ->
             lifecycle_for(event) == "completed" and
               get_in(data_field(event, :result, %{}), [:text]) == expected_text
           end)
  end

  defp assert_non_retryable_failed_path!(events, expected_category)
       when is_list(events) and is_binary(expected_category) do
    assert Enum.count(events, &(lifecycle_for(&1) == "started")) == 1
    assert Enum.count(events, &(lifecycle_for(&1) == "failed")) == 1

    refute Enum.any?(events, fn event ->
             lifecycle_for(event) == "progress" and data_field(event, :status, nil) == "retrying"
           end)

    failed_event = Enum.find(events, &(lifecycle_for(&1) == "failed"))
    assert data_field(failed_event, :error_category, nil) == expected_category
    assert data_field(failed_event, :retryable?, true) == false
  end

  defp assert_non_retryable_category_telemetry_unchanged!(baseline, expected_category)
       when is_map(baseline) and is_binary(expected_category) do
    snapshot =
      eventually(fn ->
        llm = Telemetry.snapshot().llm

        if llm.lifecycle_counts.failed >= baseline.lifecycle_counts.failed + 1 do
          {:ok, llm}
        else
          :retry
        end
      end)

    assert llm_retry_count(snapshot.retry_by_category, expected_category) ==
             llm_retry_count(baseline.retry_by_category, expected_category)
  end

  defp assert_retry_category_telemetry_increment!(baseline, expected_category)
       when is_map(baseline) and is_binary(expected_category) do
    snapshot =
      eventually(fn ->
        llm = Telemetry.snapshot().llm
        completed = llm.lifecycle_counts.completed
        retries = llm_retry_count(llm.retry_by_category, expected_category)

        if completed >= baseline.lifecycle_counts.completed + 1 and
             retries >= llm_retry_count(baseline.retry_by_category, expected_category) + 1 do
          {:ok, llm}
        else
          :retry
        end
      end)

    assert llm_retry_count(snapshot.retry_by_category, expected_category) >=
             llm_retry_count(baseline.retry_by_category, expected_category) + 1
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

  defp llm_retry_count(retry_by_category, key)
       when is_map(retry_by_category) and is_binary(key) do
    Map.get(retry_by_category, key, 0)
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
