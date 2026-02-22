defmodule Jido.Conversation.Runtime.ReducerTest do
  use ExUnit.Case, async: true

  alias Jido.Conversation.Runtime.Reducer
  alias Jido.Signal

  test "message ingress emits applied marker and start_effect directives" do
    state = Reducer.new("conversation-reducer")

    signal =
      Signal.new!("conv.in.message.received", %{message_id: "m1", ingress: "test"},
        id: "sig-1",
        source: "/tests/reducer",
        subject: "conversation-reducer",
        extensions: %{"contract_major" => 1}
      )

    assert {:ok, new_state, directives} =
             Reducer.apply_event(state, signal, priority: 1, partition_id: 0, scheduler_seq: 10)

    assert new_state.applied_count == 1
    assert new_state.stream_counts[:in] == 1
    assert new_state.last_event.id == "sig-1"

    assert Enum.any?(directives, fn directive ->
             directive.type == :emit_applied_marker and
               directive.payload.applied_event_id == "sig-1" and
               directive.cause_id == "sig-1"
           end)

    assert Enum.any?(directives, fn directive ->
             directive.type == :start_effect and
               directive.payload.class == :llm and
               directive.payload.conversation_id == "conversation-reducer"
           end)
  end

  test "applied stream events do not emit nested applied directives" do
    state = Reducer.new("conversation-reducer")

    signal =
      Signal.new!("conv.applied.event.applied", %{applied_event_id: "base-1"},
        id: "applied-1",
        source: "/tests/reducer",
        subject: "conversation-reducer",
        extensions: %{"contract_major" => 1}
      )

    assert {:ok, new_state, directives} =
             Reducer.apply_event(state, signal, priority: 2, partition_id: 0, scheduler_seq: 1)

    assert new_state.applied_count == 1
    assert new_state.stream_counts[:applied] == 1
    assert directives == []
  end

  test "effect lifecycle transitions update in_flight_effects" do
    state = Reducer.new("conversation-reducer")

    started =
      Signal.new!(
        "conv.effect.tool.execution.started",
        %{effect_id: "eff-1", lifecycle: "started"},
        id: "eff-start",
        source: "/tests/reducer",
        subject: "conversation-reducer",
        extensions: %{"contract_major" => 1}
      )

    completed =
      Signal.new!(
        "conv.effect.tool.execution.completed",
        %{effect_id: "eff-1", lifecycle: "completed"},
        id: "eff-done",
        source: "/tests/reducer",
        subject: "conversation-reducer",
        extensions: %{"contract_major" => 1}
      )

    {:ok, state_after_start, _} =
      Reducer.apply_event(state, started, priority: 2, partition_id: 0, scheduler_seq: 1)

    assert state_after_start.in_flight_effects["eff-1"] == :started

    {:ok, state_after_done, _} =
      Reducer.apply_event(state_after_start, completed,
        priority: 1,
        partition_id: 0,
        scheduler_seq: 2
      )

    refute Map.has_key?(state_after_done.in_flight_effects, "eff-1")
  end

  test "abort control event sets abort flag and emits cancel directive" do
    state = Reducer.new("conversation-reducer")

    signal =
      Signal.new!("conv.in.control.abort_requested", %{message_id: "ctrl-1", ingress: "control"},
        id: "abort-1",
        source: "/tests/reducer",
        subject: "conversation-reducer",
        extensions: %{"contract_major" => 1}
      )

    {:ok, new_state, directives} =
      Reducer.apply_event(state, signal, priority: 0, partition_id: 0, scheduler_seq: 1)

    assert new_state.flags[:abort_requested] == true

    assert Enum.any?(directives, fn directive ->
             directive.type == :cancel_effects and
               directive.payload.conversation_id == "conversation-reducer" and
               directive.payload.reason == "conv.in.control.abort_requested"
           end)
  end

  test "llm effect lifecycle emits output projection directives" do
    state = Reducer.new("conversation-reducer")

    progress =
      Signal.new!(
        "conv.effect.llm.generation.progress",
        %{effect_id: "eff-2", lifecycle: "progress", token_delta: "hello "},
        id: "eff-progress",
        source: "/tests/reducer",
        subject: "conversation-reducer",
        extensions: %{"contract_major" => 1}
      )

    completed =
      Signal.new!(
        "conv.effect.llm.generation.completed",
        %{effect_id: "eff-2", lifecycle: "completed", result: %{text: "hello world"}},
        id: "eff-completed",
        source: "/tests/reducer",
        subject: "conversation-reducer",
        extensions: %{"contract_major" => 1}
      )

    {:ok, _progress_state, progress_directives} =
      Reducer.apply_event(state, progress, priority: 2, partition_id: 0, scheduler_seq: 1)

    {:ok, _completed_state, completed_directives} =
      Reducer.apply_event(state, completed, priority: 1, partition_id: 0, scheduler_seq: 2)

    assert Enum.any?(progress_directives, fn directive ->
             directive.type == :emit_output and
               directive.payload.output_type == "conv.out.assistant.delta" and
               directive.payload.data.delta == "hello " and
               directive.payload.data.lifecycle == "progress" and
               directive.payload.data.status == "progress"
           end)

    assert Enum.any?(completed_directives, fn directive ->
             directive.type == :emit_output and
               directive.payload.output_type == "conv.out.assistant.completed" and
               directive.payload.data.content == "hello world" and
               directive.payload.data.lifecycle == "completed" and
               directive.payload.data.status == "completed"
           end)
  end

  test "llm output payload normalizes provider/model/backend metadata across backend result shapes" do
    state = Reducer.new("conversation-reducer")

    progress =
      Signal.new!(
        "conv.effect.llm.generation.progress",
        %{
          effect_id: "eff-shape",
          lifecycle: "progress",
          token_delta: "chunk-1 ",
          status: "streaming",
          provider: "anthropic",
          model: "claude-sonnet",
          backend: "jido_ai",
          attempt: 1,
          sequence: 1
        },
        id: "eff-shape-progress",
        source: "/tests/reducer",
        subject: "conversation-reducer",
        extensions: %{"contract_major" => 1}
      )

    completed =
      Signal.new!(
        "conv.effect.llm.generation.completed",
        %{
          effect_id: "eff-shape",
          lifecycle: "completed",
          result: %{
            text: "chunk-1 done",
            provider: "anthropic",
            model: "anthropic:claude-sonnet",
            finish_reason: "stop",
            usage: %{input_tokens: 3, output_tokens: 2},
            metadata: %{backend: "jido_ai", request_id: "req-1"}
          }
        },
        id: "eff-shape-completed",
        source: "/tests/reducer",
        subject: "conversation-reducer",
        extensions: %{"contract_major" => 1}
      )

    {:ok, _progress_state, progress_directives} =
      Reducer.apply_event(state, progress, priority: 2, partition_id: 0, scheduler_seq: 1)

    {:ok, _completed_state, completed_directives} =
      Reducer.apply_event(state, completed, priority: 1, partition_id: 0, scheduler_seq: 2)

    assert Enum.any?(progress_directives, fn directive ->
             directive.type == :emit_output and
               directive.payload.output_type == "conv.out.assistant.delta" and
               directive.payload.data.delta == "chunk-1 " and
               directive.payload.data.provider == "anthropic" and
               directive.payload.data.model == "claude-sonnet" and
               directive.payload.data.backend == "jido_ai" and
               directive.payload.data.status == "streaming"
           end)

    assert Enum.any?(completed_directives, fn directive ->
             directive.type == :emit_output and
               directive.payload.output_type == "conv.out.assistant.completed" and
               directive.payload.data.content == "chunk-1 done" and
               directive.payload.data.provider == "anthropic" and
               directive.payload.data.model == "anthropic:claude-sonnet" and
               directive.payload.data.backend == "jido_ai" and
               directive.payload.data.finish_reason == "stop" and
               directive.payload.data.usage == %{input_tokens: 3, output_tokens: 2} and
               directive.payload.data.metadata == %{request_id: "req-1"}
           end)
  end

  test "tool lifecycle output includes explicit status and tool identifiers" do
    state = Reducer.new("conversation-reducer")

    progress =
      Signal.new!(
        "conv.effect.tool.execution.progress",
        %{
          effect_id: "tool-eff-1",
          lifecycle: "progress",
          status: "running",
          tool_name: "web_search",
          tool_call_id: "tool-call-1",
          message: "tool in progress"
        },
        id: "tool-eff-progress",
        source: "/tests/reducer",
        subject: "conversation-reducer",
        extensions: %{"contract_major" => 1}
      )

    {:ok, _state, directives} =
      Reducer.apply_event(state, progress, priority: 2, partition_id: 0, scheduler_seq: 1)

    assert Enum.any?(directives, fn directive ->
             directive.type == :emit_output and
               directive.payload.output_type == "conv.out.tool.status" and
               directive.payload.data.effect_id == "tool-eff-1" and
               directive.payload.data.status == "running" and
               directive.payload.data.tool_name == "web_search" and
               directive.payload.data.tool_call_id == "tool-call-1"
           end)
  end

  test "llm lifecycle emits tool status output when backend payload includes tool-call status data" do
    state = Reducer.new("conversation-reducer")

    progress =
      Signal.new!(
        "conv.effect.llm.generation.progress",
        %{
          effect_id: "llm-eff-tool",
          lifecycle: "progress",
          status: "streaming",
          backend: "harness",
          provider: "codex",
          model: "best",
          tool_name: "web_search",
          tool_call_id: "call-77",
          tool_status: "started",
          tool_message: "calling web_search"
        },
        id: "llm-eff-tool-progress",
        source: "/tests/reducer",
        subject: "conversation-reducer",
        extensions: %{"contract_major" => 1}
      )

    {:ok, _state, directives} =
      Reducer.apply_event(state, progress, priority: 2, partition_id: 0, scheduler_seq: 1)

    assert Enum.any?(directives, fn directive ->
             directive.type == :emit_output and
               directive.payload.output_type == "conv.out.tool.status" and
               directive.payload.output_id == "tool-call-77" and
               directive.payload.data.status == "started" and
               directive.payload.data.message == "calling web_search" and
               directive.payload.data.tool_name == "web_search" and
               directive.payload.data.tool_call_id == "call-77" and
               directive.payload.data.backend == "harness" and
               directive.payload.data.provider == "codex"
           end)
  end
end
