defmodule Jido.Conversation.ModeErrorTest do
  use ExUnit.Case, async: true

  alias Jido.Conversation.Mode.Error

  test "metadata/1 maps unsupported mode errors" do
    assert %{
             code: :unsupported_mode,
             message: "unsupported conversation mode",
             mode: :planning,
             supported_modes: [:coding]
           } = Error.metadata({:unsupported_mode, :planning, [:coding]})
  end

  test "metadata/1 maps run-state error atoms" do
    assert %{code: :run_in_progress, message: "mode run already in progress"} =
             Error.metadata(:run_in_progress)

    assert %{code: :run_not_found, message: "mode run not found"} =
             Error.metadata(:run_not_found)

    assert %{code: :resume_not_allowed, message: "mode run cannot be resumed from current state"} =
             Error.metadata(:resume_not_allowed)
  end
end
