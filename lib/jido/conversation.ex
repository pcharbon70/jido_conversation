defmodule Jido.Conversation do
  @moduledoc """
  Agent-first conversation API built on `Jido.Agent` and `Jido.Thread`.
  """

  alias Jido.Agent
  alias Jido.Conversation.Actions.ConfigureLlm
  alias Jido.Conversation.Actions.ConfigureSkills
  alias Jido.Conversation.Actions.ReceiveUserMessage
  alias Jido.Conversation.Actions.RecordAssistantMessage
  alias Jido.Conversation.Actions.RequestCancel
  alias Jido.Conversation.Agent, as: ConversationAgent
  alias Jido.Conversation.LLMGeneration
  alias Jido.Conversation.Mode.Config, as: ModeConfig
  alias Jido.Conversation.Mode.Error, as: ModeError
  alias Jido.Conversation.Mode.Registry, as: ModeRegistry
  alias Jido.Conversation.Projections.LlmContext
  alias Jido.Conversation.Projections.Timeline
  alias Jido.Conversation.Reducer
  alias Jido.Thread
  alias Jido.Thread.Agent, as: ThreadAgent

  @type t :: Agent.t()
  @type mode_error :: ModeError.t()

  @spec supported_modes() :: [atom(), ...]
  def supported_modes, do: ModeRegistry.supported_modes()

  @spec supported_mode_metadata(keyword()) :: [ModeRegistry.mode_metadata()]
  def supported_mode_metadata(opts \\ []) when is_list(opts) do
    ModeRegistry.supported_mode_metadata(opts)
  end

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

    conversation = ConversationAgent.new(id: conversation_id, state: state)

    conversation
    |> ThreadAgent.ensure(
      id: "conv_thread_" <> conversation_id,
      metadata: %{conversation_id: conversation_id}
    )
    |> sync_state_from_thread()
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

  @spec record_assistant_message(t(), String.t(), keyword()) ::
          {:ok, t(), [struct()]} | {:error, term()}
  def record_assistant_message(%Agent{} = conversation, content, opts \\ []) when is_list(opts) do
    if blank?(content) do
      {:error, :empty_message}
    else
      params = %{
        content: content,
        metadata: normalize_map(Keyword.get(opts, :metadata, %{}))
      }

      run_action(conversation, {RecordAssistantMessage, params})
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

  @spec configure_skills(t(), [String.t() | atom()]) :: {:ok, t(), [struct()]}
  def configure_skills(%Agent{} = conversation, enabled) when is_list(enabled) do
    params = %{enabled: normalize_skills(enabled)}
    run_action(conversation, {ConfigureSkills, params})
  end

  @spec configure_mode(t(), atom(), keyword()) :: {:ok, t(), [struct()]} | {:error, mode_error()}
  def configure_mode(conversation, mode, opts \\ [])

  def configure_mode(%Agent{} = conversation, mode, opts)
      when is_atom(mode) and is_list(opts) do
    current_derived = derived_state(conversation)
    from_mode = current_derived.mode
    cause_id = Keyword.get(opts, :cause_id, Jido.Util.generate_id())
    reason = normalize_switch_reason(Keyword.get(opts, :reason, "mode_switch_requested"))

    conversation_mode_state =
      if from_mode == mode do
        normalize_map(current_derived.mode_state)
      else
        %{}
      end

    request_mode_state = normalize_map(Keyword.get(opts, :mode_state, %{}))

    with {:ok, metadata} <- ModeRegistry.fetch(mode),
         {:ok, resolved_mode_state} <-
           ModeConfig.resolve(metadata, request_mode_state, conversation_mode_state) do
      conversation =
        conversation
        |> append_note(%{
          event: "mode_switch_accepted",
          from_mode: from_mode,
          to_mode: mode,
          reason: reason,
          cause_id: cause_id
        })
        |> append_note(%{
          event: "mode_configured",
          mode: mode,
          mode_state: resolved_mode_state,
          cause_id: cause_id
        })

      {:ok, sync_state_from_thread(conversation), []}
    else
      {:error, {:unsupported_mode, unsupported_mode, supported}} ->
        {:error, {:unsupported_mode, unsupported_mode, supported}}

      {:error, diagnostics} when is_list(diagnostics) ->
        {:error, {:invalid_mode_config, mode, diagnostics}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def configure_mode(%Agent{}, mode, _opts), do: {:error, {:invalid_mode, mode}}

  @doc false
  @spec audit_mode_switch(t(), :accepted | :rejected, map()) :: t()
  def audit_mode_switch(%Agent{} = conversation, outcome, attrs \\ %{})
      when outcome in [:accepted, :rejected] and is_map(attrs) do
    event =
      case outcome do
        :accepted -> "mode_switch_accepted"
        :rejected -> "mode_switch_rejected"
      end

    payload =
      attrs
      |> normalize_map()
      |> Map.put(:event, event)

    conversation
    |> append_note(payload)
    |> sync_state_from_thread()
  end

  @spec mode(t()) :: atom()
  def mode(%Agent{} = conversation) do
    conversation
    |> derived_state()
    |> Map.get(:mode, :coding)
  end

  @spec generate_assistant_reply(t(), keyword()) ::
          {:ok, t(), JidoConversation.LLM.Result.t()} | {:error, JidoConversation.LLM.Error.t()}
  def generate_assistant_reply(%Agent{} = conversation, opts \\ []) when is_list(opts) do
    LLMGeneration.generate(conversation, opts)
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

  @spec derived_state(t()) :: Reducer.derived_state()
  def derived_state(%Agent{} = conversation) do
    Reducer.derive(thread_entries(conversation), default_llm: default_llm(conversation))
  end

  @spec messages(t(), keyword()) :: [map()]
  def messages(%Agent{} = conversation, opts \\ []) when is_list(opts) do
    messages =
      conversation
      |> derived_state()
      |> Map.get(:messages, [])

    messages
    |> maybe_filter_roles(Keyword.get(opts, :roles))
    |> tail_messages(Keyword.get(opts, :max_messages))
  end

  @spec timeline(t()) :: [Timeline.entry()]
  def timeline(%Agent{} = conversation) do
    conversation
    |> thread_entries()
    |> Timeline.from_entries()
  end

  @spec llm_context(t(), keyword()) :: [LlmContext.message()]
  def llm_context(%Agent{} = conversation, opts \\ []) do
    conversation
    |> thread_entries()
    |> LlmContext.from_entries(opts)
  end

  @spec state(t()) :: map()
  def state(%Agent{} = conversation), do: conversation.state

  defp append_note(%Agent{} = conversation, payload) when is_map(payload) do
    conversation
    |> ThreadAgent.ensure(metadata: %{conversation_id: conversation.id})
    |> ThreadAgent.append(%{kind: :note, payload: payload})
  end

  defp run_action(%Agent{} = conversation, action) do
    {next_conversation, directives} = ConversationAgent.cmd(conversation, action)
    {:ok, sync_state_from_thread(next_conversation), directives}
  end

  defp sync_state_from_thread(%Agent{} = conversation) do
    derived = derived_state(conversation)
    %Agent{conversation | state: Map.merge(conversation.state, derived)}
  end

  defp default_llm(%Agent{} = conversation) do
    conversation.state
    |> Map.get(:llm, %{})
    |> normalize_map()
    |> Map.put_new(:backend, :jido_ai)
    |> Map.put_new(:provider, nil)
    |> Map.put_new(:model, nil)
    |> Map.put_new(:options, %{})
  end

  defp conversation_id_from_opts(opts_map) do
    opts_map[:conversation_id] || opts_map[:id] || Jido.Util.generate_id()
  end

  defp normalize_opts(opts) when is_list(opts), do: Map.new(opts)
  defp normalize_opts(opts) when is_map(opts), do: opts
  defp normalize_opts(_), do: %{}

  defp normalize_skills(enabled) when is_list(enabled) do
    enabled
    |> Enum.map(fn
      skill when is_atom(skill) -> Atom.to_string(skill)
      skill when is_binary(skill) -> String.trim(skill)
      _other -> ""
    end)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp normalize_map(value) when is_map(value), do: value
  defp normalize_map(_), do: %{}

  defp normalize_switch_reason(reason) when is_binary(reason) do
    trimmed = String.trim(reason)
    if trimmed == "", do: "mode_switch_requested", else: trimmed
  end

  defp normalize_switch_reason(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp normalize_switch_reason(_reason), do: "mode_switch_requested"

  defp maybe_filter_roles(messages, nil), do: messages

  defp maybe_filter_roles(messages, roles) when is_list(roles) do
    role_set =
      roles
      |> Enum.map(&normalize_message_role/1)
      |> Enum.reject(&is_nil/1)
      |> MapSet.new()

    if MapSet.size(role_set) == 0 do
      []
    else
      Enum.filter(messages, &MapSet.member?(role_set, &1.role))
    end
  end

  defp maybe_filter_roles(messages, _roles), do: messages

  defp tail_messages(messages, max_messages) when is_integer(max_messages) and max_messages > 0 do
    Enum.take(messages, -max_messages)
  end

  defp tail_messages(messages, _max_messages), do: messages

  defp normalize_message_role("user"), do: :user
  defp normalize_message_role("assistant"), do: :assistant
  defp normalize_message_role("system"), do: :system
  defp normalize_message_role("tool"), do: :tool
  defp normalize_message_role(role) when role in [:user, :assistant, :system, :tool], do: role
  defp normalize_message_role(_), do: nil

  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(_), do: true
end
