defmodule Jido.Conversation.Mode.Coding do
  @moduledoc """
  Built-in coding mode contract.
  """

  @behaviour Jido.Conversation.Mode

  @impl true
  @spec id() :: :coding
  def id, do: :coding

  def summary, do: "Default coding-focused conversation mode."

  def capabilities do
    %{
      interruptible?: true,
      planning?: false,
      architecture_dialog?: false
    }
  end

  def required_options, do: []

  def optional_options, do: [:style, :max_turns]

  def defaults, do: %{}

  def unknown_keys_policy, do: :allow

  def stability, do: :stable

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
