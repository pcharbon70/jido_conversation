defmodule Jido.Conversation.Mode.Engineering do
  @moduledoc """
  Built-in engineering mode contract.
  """

  @behaviour Jido.Conversation.Mode

  @impl true
  @spec id() :: :engineering
  def id, do: :engineering

  def summary, do: "Collaborative engineering mode for architecture and tradeoff design."

  def capabilities do
    %{
      interruptible?: true,
      planning?: false,
      architecture_dialog?: true
    }
  end

  def required_options, do: [:topic]

  def optional_options, do: [:constraints, :stakeholders, :max_options]

  def defaults, do: %{max_options: 3}

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
