defmodule Jido.Conversation do
  @moduledoc """
  Agent-first conversation API built on `Jido.Agent` and `Jido.Thread`.
  """

  alias Jido.Agent
  alias Jido.Conversation.Actions.ConfigureLlm
  alias Jido.Conversation.Actions.ReceiveUserMessage
  alias Jido.Conversation.Actions.RequestCancel
  alias Jido.Conversation.Agent, as: ConversationAgent
  alias Jido.Thread
  alias Jido.Thread.Agent, as: ThreadAgent

  @type t :: Agent.t()

  @spec new(keyword() | map()) :: t()
  def new(opts \\ []) do
    opts_map = normalize_opts(opts)
    conversation_id = conversation_id_from_opts(opts_map)

    state =
      opts_map
      |> Map.get(:state, %{})
      |> normalize_map()
      |> Map.put_new(:conversation_id, conversation_id)
      |> Map.put_new(:metadata, normalize_map(Map.get(opts_map, :metadata, %{})))

    agent = ConversationAgent.new(id: conversation_id, state: state)

    ThreadAgent.ensure(agent,
      id: "conv_thread_" <> conversation_id,
      metadata: %{conversation_id: conversation_id}
    )
  end

  @spec send_user_message(t(), String.t(), keyword()) :: {:ok, t(), [struct()]} | {:error, term()}
  def send_user_message(%Agent{} = conversation, content, opts \\ []) when is_list(opts) do
    if blank?(content) do
      {:error, :empty_message}
    else
      params = %{
        content: content,
        metadata: normalize_map(Keyword.get(opts, :metadata, %{}))
      }

      run_action(conversation, {ReceiveUserMessage, params})
    end
  end

  @spec cancel(t(), String.t()) :: {:ok, t(), [struct()]}
  def cancel(%Agent{} = conversation, reason \\ "cancel_requested") do
    run_action(conversation, {RequestCancel, %{reason: reason}})
  end

  @spec configure_llm(t(), atom(), keyword()) :: {:ok, t(), [struct()]}
  def configure_llm(%Agent{} = conversation, backend, opts \\ [])
      when is_atom(backend) and is_list(opts) do
    params = %{
      backend: backend,
      provider: Keyword.get(opts, :provider),
      model: Keyword.get(opts, :model),
      options: normalize_map(Keyword.get(opts, :options, %{}))
    }

    run_action(conversation, {ConfigureLlm, params})
  end

  @spec thread(t()) :: Thread.t() | nil
  def thread(%Agent{} = conversation) do
    ThreadAgent.get(conversation)
  end

  @spec thread_entries(t()) :: [Jido.Thread.Entry.t()]
  def thread_entries(%Agent{} = conversation) do
    case thread(conversation) do
      nil -> []
      %Thread{} = thread -> Thread.to_list(thread)
    end
  end

  @spec state(t()) :: map()
  def state(%Agent{} = conversation), do: conversation.state

  defp run_action(%Agent{} = conversation, action) do
    {next_conversation, directives} = ConversationAgent.cmd(conversation, action)
    {:ok, next_conversation, directives}
  end

  defp conversation_id_from_opts(opts_map) do
    opts_map[:conversation_id] || opts_map[:id] || Jido.Util.generate_id()
  end

  defp normalize_opts(opts) when is_list(opts), do: Map.new(opts)
  defp normalize_opts(opts) when is_map(opts), do: opts
  defp normalize_opts(_), do: %{}

  defp normalize_map(value) when is_map(value), do: value
  defp normalize_map(_), do: %{}

  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(_), do: true
end
