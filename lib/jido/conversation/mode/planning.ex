defmodule Jido.Conversation.Mode.Planning do
  @moduledoc """
  Built-in planning mode contract.
  """

  @behaviour Jido.Conversation.Mode

  @impl true
  @spec id() :: :planning
  def id, do: :planning

  def summary, do: "Structured planning mode for phased implementation plans."

  def capabilities do
    %{
      interruptible?: true,
      planning?: true,
      architecture_dialog?: false
    }
  end

  def required_options, do: [:objective]

  def optional_options, do: [:constraints, :output_format, :max_phases]

  def defaults, do: %{output_format: :markdown, max_phases: 6}

  def unknown_keys_policy, do: :reject

  def stability, do: :experimental

  def version, do: 1

  @impl true
  def init(_conversation_state, _opts), do: {:ok, %{}, []}

  @impl true
  def plan_next_step(mode_state, _run_state, _opts), do: {:complete, mode_state, []}

  @impl true
  def handle_effect_event(mode_state, _run_state, _signal, _opts), do: {:ok, mode_state, []}

  @impl true
  def interrupt(mode_state, _run_state, _reason, _opts), do: {:ok, mode_state, []}

  @impl true
  def resume(mode_state, _run_state, _opts), do: {:ok, mode_state, []}

  @impl true
  def finalize(mode_state, _run_state, _reason, _opts), do: {:complete, mode_state, []}
end
