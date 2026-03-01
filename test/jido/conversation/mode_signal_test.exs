defmodule Jido.Conversation.ModeSignalTest do
  use ExUnit.Case, async: true

  alias Jido.Conversation.Mode.Signal, as: ModeSignal
  alias Jido.Signal

  test "validates mode lifecycle signal payload with cause-link metadata" do
    {:ok, signal} =
      Signal.new(
        "conv.in.mode.run.started",
        %{
          mode: :coding,
          run_id: "run-1",
          step_id: "step-1",
          status: :running,
          reason: "start",
          cause_id: "cause-1"
        },
        source: "/conversation/runtime",
        subject: "conv-mode-1",
        extensions: %{contract_major: 1}
      )

    assert :ok = ModeSignal.validate(signal)
  end

  test "validates mode control signal payload contract" do
    {:ok, signal} =
      Signal.new(
        "conv.in.control.mode.interrupt_requested",
        %{
          mode: :coding,
          run_id: "run-2",
          action: :interrupt,
          reason: "user_request",
          cause_id: "cause-2"
        },
        source: "/conversation/runtime",
        subject: "conv-mode-2",
        extensions: %{contract_major: 1}
      )

    assert :ok = ModeSignal.validate(signal)
  end

  test "rejects mode lifecycle signal missing required fields" do
    {:ok, signal} =
      Signal.new(
        "conv.out.mode.step.completed",
        %{
          mode: :coding,
          run_id: "run-3",
          step_id: "step-3",
          status: :completed,
          reason: "done"
        },
        source: "/conversation/runtime",
        subject: "conv-mode-3",
        extensions: %{contract_major: 1}
      )

    assert {:error, {:payload, {:missing_keys, [:cause_id]}}} = ModeSignal.validate(signal)
  end

  test "rejects mode lifecycle signal with unsupported contract major" do
    {:ok, signal} =
      Signal.new(
        "conv.out.mode.run.completed",
        %{
          mode: :coding,
          run_id: "run-4",
          step_id: nil,
          status: :completed,
          reason: "done",
          cause_id: "cause-4"
        },
        source: "/conversation/runtime",
        subject: "conv-mode-4",
        extensions: %{contract_major: 2}
      )

    assert {:error, {:contract_major, {:unsupported, 2}}} = ModeSignal.validate(signal)
  end
end
