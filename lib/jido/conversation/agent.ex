defmodule Jido.Conversation.Agent do
  @moduledoc """
  Core conversation agent built on `Jido.Agent`.

  This is the new runtime nucleus for the agent-first architecture. It keeps
  conversation state in the agent struct and an append-only interaction journal
  in `:__thread__`.
  """

  use Jido.Agent,
    name: "conversation_agent",
    description: "Event-sourced conversation agent",
    schema: [
      conversation_id: [type: :string, required: true],
      status: [type: {:in, [:idle, :pending_llm, :responding, :canceled, :error]}, default: :idle],
      turn: [type: :integer, default: 0],
      messages: [type: :list, default: []],
      metadata: [type: :map, default: %{}],
      cancel_requested?: [type: :boolean, default: false],
      llm: [type: :map, default: %{backend: :jido_ai, provider: nil, model: nil, options: %{}}],
      skills: [type: :map, default: %{enabled: []}],
      mode: [type: :atom, default: :coding],
      mode_state: [type: :map, default: %{}],
      active_run: [type: :any, default: nil],
      run_history: [type: :list, default: []]
    ],
    strategy: {Jido.Agent.Strategy.Direct, thread?: true}

  alias Jido.Conversation.Actions.ConfigureLlm
  alias Jido.Conversation.Actions.ConfigureSkills
  alias Jido.Conversation.Actions.ReceiveUserMessage
  alias Jido.Conversation.Actions.RecordAssistantMessage
  alias Jido.Conversation.Actions.RequestCancel
  alias Jido.Thread.Agent, as: ThreadAgent

  @impl true
  def on_before_cmd(agent, action) do
    agent = ThreadAgent.ensure(agent, metadata: %{conversation_id: agent.id})
    {:ok, append_command_entry(agent, action), action}
  end

  @impl true
  def on_after_cmd(agent, action, directives) do
    payload = %{
      event: "command_applied",
      action: action_name(action),
      directives: length(directives)
    }

    {:ok, ThreadAgent.append(agent, %{kind: :note, payload: payload}), directives}
  end

  defp append_command_entry(agent, {ReceiveUserMessage, params}) when is_map(params) do
    append_message_entry(agent, params, "user")
  end

  defp append_command_entry(agent, {RecordAssistantMessage, params}) when is_map(params) do
    append_message_entry(agent, params, "assistant")
  end

  defp append_command_entry(agent, {RequestCancel, params}) when is_map(params) do
    reason = params[:reason] || params["reason"] || "cancel_requested"

    ThreadAgent.append(agent, %{
      kind: :note,
      payload: %{
        event: "cancel_requested",
        reason: reason
      }
    })
  end

  defp append_command_entry(agent, {ConfigureLlm, params}) when is_map(params) do
    ThreadAgent.append(agent, %{
      kind: :note,
      payload: %{
        event: "llm_configured",
        backend: params[:backend] || params["backend"],
        provider: params[:provider] || params["provider"],
        model: params[:model] || params["model"],
        options: params[:options] || params["options"] || %{}
      }
    })
  end

  defp append_command_entry(agent, {ConfigureSkills, params}) when is_map(params) do
    ThreadAgent.append(agent, %{
      kind: :note,
      payload: %{
        event: "skills_configured",
        enabled: params[:enabled] || params["enabled"] || []
      }
    })
  end

  defp append_command_entry(agent, _action), do: agent

  defp append_message_entry(agent, params, role) do
    content = params[:content] || params["content"]

    ThreadAgent.append(agent, %{
      kind: :message,
      payload: %{
        role: role,
        content: content,
        metadata: params[:metadata] || params["metadata"] || %{}
      }
    })
  end

  defp action_name({module, _params}) when is_atom(module), do: Atom.to_string(module)
  defp action_name(module) when is_atom(module), do: Atom.to_string(module)
  defp action_name(_action), do: "unknown"
end
