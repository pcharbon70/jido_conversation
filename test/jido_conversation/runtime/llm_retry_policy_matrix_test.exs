defmodule JidoConversation.Runtime.LLMRetryPolicyMatrixTest do
  use ExUnit.Case, async: false

  alias JidoConversation.Ingest
  alias JidoConversation.Runtime.Coordinator
  alias JidoConversation.Runtime.EffectManager
  alias JidoConversation.Runtime.IngressSubscriber
  alias JidoConversation.Telemetry

  @app :jido_conversation
  @key JidoConversation.EventSystem

  defmodule RetryMatrixJidoAI do
    def resolve_model(:fast), do: "openai:gpt-4o-mini"
    def resolve_model(:capable), do: "openai:gpt-4o"
    def resolve_model(model) when is_binary(model), do: model
    def resolve_model(_), do: "openai:gpt-4o-mini"
  end

  defmodule RetryMatrixLLMClient do
    def generate_text(context, model, _messages, _opts) do
      attempt = next_attempt(context.counter)

      send(context.test_pid, {:jido_ai_generate_text, context.scenario, attempt, model})

      case context.scenario do
        :non_retryable_422 ->
          {:error, %{status: 422, message: "unprocessable_entity"}}

        :auth_401 ->
          {:error, %{status: 401, message: "unauthorized"}}

        :config_error ->
          {:error, ArgumentError.exception("invalid request configuration")}

        :unknown_error ->
          {:error, %{message: "unexpected_failure"}}

        :retryable_then_success ->
          scenario_recovery_result(attempt, model, :provider, "jido_ai recovered")

        :timeout_then_success ->
          scenario_recovery_result(attempt, model, :timeout, "jido_ai timeout recovered")

        :transport_then_success ->
          scenario_recovery_result(attempt, model, :transport, "jido_ai transport recovered")
      end
    end

    defp next_attempt(counter) when is_pid(counter) do
      Agent.get_and_update(counter, fn value ->
        next = value + 1
        {next, next}
      end)
    end

    defp scenario_recovery_result(1, _model, :provider, _content) do
      {:error, %{status: 503, message: "service_unavailable"}}
    end

    defp scenario_recovery_result(1, _model, :timeout, _content) do
      {:error, %{reason: :timeout, message: "request_timeout"}}
    end

    defp scenario_recovery_result(1, _model, :transport, _content) do
      {:error, %{reason: :econnrefused, message: "network_down"}}
    end

    defp scenario_recovery_result(_attempt, model, _kind, content) do
      {:ok,
       %{
         model: model,
         finish_reason: :stop,
         message: %{content: content},
         usage: %{input_tokens: 2, output_tokens: 3}
       }}
    end
  end

  defmodule RetryMatrixHarness do
    def run(provider, prompt, opts)
        when is_atom(provider) and is_binary(prompt) and is_list(opts) do
      scenario = Keyword.fetch!(opts, :scenario)
      counter = Keyword.fetch!(opts, :counter)
      test_pid = Keyword.get(opts, :test_pid, self())
      attempt = next_attempt(counter)

      send(test_pid, {:harness_run, scenario, attempt, provider})
      run_scenario_result(scenario, attempt, provider)
    end

    def run(prompt, opts) when is_binary(prompt) and is_list(opts) do
      run(:codex, prompt, opts)
    end

    def cancel(_provider, _session_id), do: :ok

    defp run_scenario_result(:non_retryable_422, _attempt, _provider) do
      {:error, %{status: 422, message: "invalid_request"}}
    end

    defp run_scenario_result(:auth_403, _attempt, _provider) do
      {:error, %{status: 403, message: "forbidden"}}
    end

    defp run_scenario_result(:config_error, _attempt, _provider) do
      {:error, ArgumentError.exception("invalid harness configuration")}
    end

    defp run_scenario_result(:unknown_error, _attempt, _provider) do
      {:error, %{message: "harness_unexpected_failure"}}
    end

    defp run_scenario_result(:retryable_then_success, attempt, provider) do
      scenario_recovery_result(attempt, provider, :provider, "harness recovered")
    end

    defp run_scenario_result(:timeout_then_success, attempt, provider) do
      scenario_recovery_result(attempt, provider, :timeout, "harness timeout recovered")
    end

    defp run_scenario_result(:transport_then_success, attempt, provider) do
      scenario_recovery_result(attempt, provider, :transport, "harness transport recovered")
    end

    defp next_attempt(counter) when is_pid(counter) do
      Agent.get_and_update(counter, fn value ->
        next = value + 1
        {next, next}
      end)
    end

    defp scenario_recovery_result(1, _provider, :provider, _text) do
      {:error, %{status: 503, message: "upstream_unavailable"}}
    end

    defp scenario_recovery_result(1, _provider, :timeout, _text) do
      {:error, %{reason: :timeout, message: "request_timeout"}}
    end

    defp scenario_recovery_result(1, _provider, :transport, _text) do
      {:error, %{reason: :econnrefused, message: "network_down"}}
    end

    defp scenario_recovery_result(_attempt, provider, _kind, text) do
      {:ok,
       [
         %{
           type: :session_completed,
           provider: provider,
           payload: %{
             "output_text" => text,
             "usage" => %{"input_tokens" => 1, "output_tokens" => 2}
           }
         }
       ]}
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

  test "jido_ai 4xx provider errors are non-retryable at runtime" do
    counter = start_counter!()
    put_runtime_backend!(:jido_ai, llm_client_context(:non_retryable_422, counter))
    :ok = Telemetry.reset()
    baseline = Telemetry.snapshot().llm

    conversation_id = unique_id("conversation-jido-ai-non-retryable")
    effect_id = unique_id("effect-jido-ai-non-retryable")
    replay_start = DateTime.utc_now() |> DateTime.to_unix()

    :ok =
      EffectManager.start_effect(
        %{
          effect_id: effect_id,
          conversation_id: conversation_id,
          class: :llm,
          kind: "generation",
          input: %{content: "trigger non-retryable"},
          policy: %{max_attempts: 3, backoff_ms: 5, timeout_ms: 800}
        },
        nil
      )

    assert_receive {:jido_ai_generate_text, :non_retryable_422, 1, _model}
    refute_receive {:jido_ai_generate_text, :non_retryable_422, 2, _model}, 200

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
        failed = llm.lifecycle_counts.failed

        if failed >= baseline.lifecycle_counts.failed + 1 do
          {:ok, llm}
        else
          :retry
        end
      end)

    assert llm_retry_count(snapshot.retry_by_category, "provider") ==
             llm_retry_count(baseline.retry_by_category, "provider")
  end

  test "jido_ai transient provider failures retry and complete" do
    counter = start_counter!()
    put_runtime_backend!(:jido_ai, llm_client_context(:retryable_then_success, counter))
    :ok = Telemetry.reset()
    baseline = Telemetry.snapshot().llm

    conversation_id = unique_id("conversation-jido-ai-retryable")
    effect_id = unique_id("effect-jido-ai-retryable")
    replay_start = DateTime.utc_now() |> DateTime.to_unix()

    :ok =
      EffectManager.start_effect(
        %{
          effect_id: effect_id,
          conversation_id: conversation_id,
          class: :llm,
          kind: "generation",
          input: %{content: "trigger retry then success"},
          policy: %{max_attempts: 3, backoff_ms: 5, timeout_ms: 800}
        },
        nil
      )

    assert_receive {:jido_ai_generate_text, :retryable_then_success, 1, _model}
    assert_receive {:jido_ai_generate_text, :retryable_then_success, 2, _model}

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
               get_in(data_field(event, :result, %{}), [:text]) == "jido_ai recovered"
           end)

    assert Agent.get(counter, & &1) == 2

    snapshot =
      eventually(fn ->
        llm = Telemetry.snapshot().llm
        completed = llm.lifecycle_counts.completed
        retries = llm_retry_count(llm.retry_by_category, "provider")

        if completed >= baseline.lifecycle_counts.completed + 1 and
             retries >= llm_retry_count(baseline.retry_by_category, "provider") + 1 do
          {:ok, llm}
        else
          :retry
        end
      end)

    assert llm_retry_count(snapshot.retry_by_category, "provider") >=
             llm_retry_count(baseline.retry_by_category, "provider") + 1
  end

  test "jido_ai auth failures are non-retryable and emit auth category at runtime" do
    counter = start_counter!()
    put_runtime_backend!(:jido_ai, llm_client_context(:auth_401, counter))
    baseline = reset_llm_baseline!()
    conversation_id = unique_id("conversation-jido-ai-auth-non-retryable")
    effect_id = unique_id("effect-jido-ai-auth-non-retryable")
    replay_start = DateTime.utc_now() |> DateTime.to_unix()

    start_retry_category_effect!(effect_id, conversation_id)

    assert_receive {:jido_ai_generate_text, :auth_401, 1, _model}
    refute_receive {:jido_ai_generate_text, :auth_401, 2, _model}, 200

    events = await_failed_llm_effect_events(effect_id, replay_start)
    assert_non_retryable_failed_path!(events, "auth")
    assert Agent.get(counter, & &1) == 1

    assert_non_retryable_category_telemetry_unchanged!(baseline, "auth")
  end

  test "jido_ai config failures are non-retryable and emit config category at runtime" do
    counter = start_counter!()
    put_runtime_backend!(:jido_ai, llm_client_context(:config_error, counter))
    baseline = reset_llm_baseline!()
    conversation_id = unique_id("conversation-jido-ai-config-non-retryable")
    effect_id = unique_id("effect-jido-ai-config-non-retryable")
    replay_start = DateTime.utc_now() |> DateTime.to_unix()

    start_retry_category_effect!(effect_id, conversation_id)

    assert_receive {:jido_ai_generate_text, :config_error, 1, _model}
    refute_receive {:jido_ai_generate_text, :config_error, 2, _model}, 200

    events = await_failed_llm_effect_events(effect_id, replay_start)
    assert_non_retryable_failed_path!(events, "config")
    assert Agent.get(counter, & &1) == 1

    assert_non_retryable_category_telemetry_unchanged!(baseline, "config")
  end

  test "jido_ai unknown failures are non-retryable and emit unknown category at runtime" do
    counter = start_counter!()
    put_runtime_backend!(:jido_ai, llm_client_context(:unknown_error, counter))
    baseline = reset_llm_baseline!()
    conversation_id = unique_id("conversation-jido-ai-unknown-non-retryable")
    effect_id = unique_id("effect-jido-ai-unknown-non-retryable")
    replay_start = DateTime.utc_now() |> DateTime.to_unix()

    start_retry_category_effect!(effect_id, conversation_id)

    assert_receive {:jido_ai_generate_text, :unknown_error, 1, _model}
    refute_receive {:jido_ai_generate_text, :unknown_error, 2, _model}, 200

    events = await_failed_llm_effect_events(effect_id, replay_start)
    assert_non_retryable_failed_path!(events, "unknown")
    assert Agent.get(counter, & &1) == 1

    assert_non_retryable_category_telemetry_unchanged!(baseline, "unknown")
  end

  test "harness 4xx provider errors are non-retryable at runtime" do
    counter = start_counter!()
    put_runtime_backend!(:harness, %{})
    :ok = Telemetry.reset()
    baseline = Telemetry.snapshot().llm

    conversation_id = unique_id("conversation-harness-non-retryable")
    effect_id = unique_id("effect-harness-non-retryable")
    replay_start = DateTime.utc_now() |> DateTime.to_unix()

    :ok =
      EffectManager.start_effect(
        %{
          effect_id: effect_id,
          conversation_id: conversation_id,
          class: :llm,
          kind: "generation",
          input: %{
            content: "trigger harness non-retryable",
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

    assert_receive {:harness_run, :non_retryable_422, 1, :codex}
    refute_receive {:harness_run, :non_retryable_422, 2, :codex}, 200

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
        failed = llm.lifecycle_counts.failed

        if failed >= baseline.lifecycle_counts.failed + 1 do
          {:ok, llm}
        else
          :retry
        end
      end)

    assert llm_retry_count(snapshot.retry_by_category, "provider") ==
             llm_retry_count(baseline.retry_by_category, "provider")
  end

  test "harness transient provider failures retry and complete" do
    counter = start_counter!()
    put_runtime_backend!(:harness, %{})
    :ok = Telemetry.reset()
    baseline = Telemetry.snapshot().llm

    conversation_id = unique_id("conversation-harness-retryable")
    effect_id = unique_id("effect-harness-retryable")
    replay_start = DateTime.utc_now() |> DateTime.to_unix()

    :ok =
      EffectManager.start_effect(
        %{
          effect_id: effect_id,
          conversation_id: conversation_id,
          class: :llm,
          kind: "generation",
          input: %{
            content: "trigger harness retry then success",
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

    assert_receive {:harness_run, :retryable_then_success, 1, :codex}
    assert_receive {:harness_run, :retryable_then_success, 2, :codex}

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
               get_in(data_field(event, :result, %{}), [:text]) == "harness recovered"
           end)

    assert Agent.get(counter, & &1) == 2

    snapshot =
      eventually(fn ->
        llm = Telemetry.snapshot().llm
        completed = llm.lifecycle_counts.completed
        retries = llm_retry_count(llm.retry_by_category, "provider")

        if completed >= baseline.lifecycle_counts.completed + 1 and
             retries >= llm_retry_count(baseline.retry_by_category, "provider") + 1 do
          {:ok, llm}
        else
          :retry
        end
      end)

    assert llm_retry_count(snapshot.retry_by_category, "provider") >=
             llm_retry_count(baseline.retry_by_category, "provider") + 1
  end

  test "harness auth failures are non-retryable and emit auth category at runtime" do
    counter = start_counter!()
    put_runtime_backend!(:harness, %{})
    baseline = reset_llm_baseline!()
    conversation_id = unique_id("conversation-harness-auth-non-retryable")
    effect_id = unique_id("effect-harness-auth-non-retryable")
    replay_start = DateTime.utc_now() |> DateTime.to_unix()

    start_retry_category_effect!(
      effect_id,
      conversation_id,
      %{request_options: %{scenario: :auth_403, counter: counter, test_pid: self()}}
    )

    assert_receive {:harness_run, :auth_403, 1, :codex}
    refute_receive {:harness_run, :auth_403, 2, :codex}, 200

    events = await_failed_llm_effect_events(effect_id, replay_start)
    assert_non_retryable_failed_path!(events, "auth")
    assert Agent.get(counter, & &1) == 1

    assert_non_retryable_category_telemetry_unchanged!(baseline, "auth")
  end

  test "harness config failures are non-retryable and emit config category at runtime" do
    counter = start_counter!()
    put_runtime_backend!(:harness, %{})
    baseline = reset_llm_baseline!()
    conversation_id = unique_id("conversation-harness-config-non-retryable")
    effect_id = unique_id("effect-harness-config-non-retryable")
    replay_start = DateTime.utc_now() |> DateTime.to_unix()

    start_retry_category_effect!(
      effect_id,
      conversation_id,
      %{request_options: %{scenario: :config_error, counter: counter, test_pid: self()}}
    )

    assert_receive {:harness_run, :config_error, 1, :codex}
    refute_receive {:harness_run, :config_error, 2, :codex}, 200

    events = await_failed_llm_effect_events(effect_id, replay_start)
    assert_non_retryable_failed_path!(events, "config")
    assert Agent.get(counter, & &1) == 1

    assert_non_retryable_category_telemetry_unchanged!(baseline, "config")
  end

  test "harness unknown failures are non-retryable and emit unknown category at runtime" do
    counter = start_counter!()
    put_runtime_backend!(:harness, %{})
    baseline = reset_llm_baseline!()
    conversation_id = unique_id("conversation-harness-unknown-non-retryable")
    effect_id = unique_id("effect-harness-unknown-non-retryable")
    replay_start = DateTime.utc_now() |> DateTime.to_unix()

    start_retry_category_effect!(
      effect_id,
      conversation_id,
      %{request_options: %{scenario: :unknown_error, counter: counter, test_pid: self()}}
    )

    assert_receive {:harness_run, :unknown_error, 1, :codex}
    refute_receive {:harness_run, :unknown_error, 2, :codex}, 200

    events = await_failed_llm_effect_events(effect_id, replay_start)
    assert_non_retryable_failed_path!(events, "unknown")
    assert Agent.get(counter, & &1) == 1

    assert_non_retryable_category_telemetry_unchanged!(baseline, "unknown")
  end

  test "jido_ai timeout failures retry and increment timeout retry telemetry category" do
    assert_retry_category_recovery_jido_ai(
      :timeout_then_success,
      "timeout",
      "jido_ai timeout recovered"
    )
  end

  test "jido_ai transport failures retry and increment transport retry telemetry category" do
    assert_retry_category_recovery_jido_ai(
      :transport_then_success,
      "transport",
      "jido_ai transport recovered"
    )
  end

  test "harness timeout failures retry and increment timeout retry telemetry category" do
    assert_retry_category_recovery_harness(
      :timeout_then_success,
      "timeout",
      "harness timeout recovered"
    )
  end

  test "harness transport failures retry and increment transport retry telemetry category" do
    assert_retry_category_recovery_harness(
      :transport_then_success,
      "transport",
      "harness transport recovered"
    )
  end

  defp put_runtime_backend!(:jido_ai, llm_client_context) when is_map(llm_client_context) do
    Application.put_env(@app, @key,
      llm: [
        default_backend: :jido_ai,
        default_stream?: false,
        default_timeout_ms: 800,
        default_provider: "openai",
        default_model: "openai:gpt-4o-mini",
        backends: [
          jido_ai: [
            module: JidoConversation.LLM.Adapters.JidoAI,
            stream?: false,
            timeout_ms: 800,
            provider: "openai",
            model: "openai:gpt-4o-mini",
            options: [
              llm_client_module: RetryMatrixLLMClient,
              jido_ai_module: RetryMatrixJidoAI,
              llm_client_context: llm_client_context
            ]
          ],
          harness: [
            module: nil,
            stream?: false,
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
        default_stream?: false,
        default_timeout_ms: 800,
        default_provider: nil,
        default_model: nil,
        backends: [
          jido_ai: [
            module: nil,
            stream?: false,
            timeout_ms: 800,
            provider: nil,
            model: nil,
            options: []
          ],
          harness: [
            module: JidoConversation.LLM.Adapters.Harness,
            stream?: false,
            timeout_ms: 800,
            provider: "codex",
            model: nil,
            options: [
              harness_module: RetryMatrixHarness,
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
              :config_error,
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
    conversation_id = unique_id("conversation-jido-ai-#{scenario}")
    effect_id = unique_id("effect-jido-ai-#{scenario}")
    replay_start = DateTime.utc_now() |> DateTime.to_unix()

    start_retry_category_effect!(effect_id, conversation_id)

    assert_receive {:jido_ai_generate_text, ^scenario, 1, _model}
    assert_receive {:jido_ai_generate_text, ^scenario, 2, _model}

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
    conversation_id = unique_id("conversation-harness-#{scenario}")
    effect_id = unique_id("effect-harness-#{scenario}")
    replay_start = DateTime.utc_now() |> DateTime.to_unix()

    start_retry_category_effect!(
      effect_id,
      conversation_id,
      %{request_options: %{scenario: scenario, counter: counter, test_pid: self()}}
    )

    assert_receive {:harness_run, ^scenario, 1, :codex}
    assert_receive {:harness_run, ^scenario, 2, :codex}

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
        content: "retry category path"
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
