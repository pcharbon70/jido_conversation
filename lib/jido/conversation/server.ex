defmodule Jido.Conversation.Server do
  @moduledoc """
  Process wrapper around `Jido.Conversation` with async generation and cancellation.
  """

  use GenServer

  alias Jido.Conversation
  alias JidoConversation.LLM.Error, as: LLMError

  @type active_generation :: %{
          task: Task.t(),
          generation_ref: reference(),
          reply_to: pid()
        }

  @type state :: %{
          conversation: Conversation.t(),
          active_generation: active_generation() | nil
        }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) when is_list(opts) do
    {name, conversation_opts} = Keyword.pop(opts, :name)

    genserver_opts =
      case name do
        nil -> []
        value -> [name: value]
      end

    GenServer.start_link(__MODULE__, conversation_opts, genserver_opts)
  end

  @spec conversation(GenServer.server()) :: Conversation.t()
  def conversation(server) do
    GenServer.call(server, :conversation)
  end

  @spec derived_state(GenServer.server()) :: map()
  def derived_state(server) do
    GenServer.call(server, :derived_state)
  end

  @spec timeline(GenServer.server()) :: [map()]
  def timeline(server) do
    GenServer.call(server, :timeline)
  end

  @spec thread(GenServer.server()) :: Jido.Thread.t() | nil
  def thread(server) do
    GenServer.call(server, :thread)
  end

  @spec messages(GenServer.server(), keyword()) :: [map()]
  def messages(server, opts \\ []) when is_list(opts) do
    GenServer.call(server, {:messages, opts})
  end

  @spec thread_entries(GenServer.server()) :: [Jido.Thread.Entry.t()]
  def thread_entries(server) do
    GenServer.call(server, :thread_entries)
  end

  @spec llm_context(GenServer.server(), keyword()) :: [map()]
  def llm_context(server, opts \\ []) when is_list(opts) do
    GenServer.call(server, {:llm_context, opts})
  end

  @spec mode(GenServer.server()) :: atom()
  def mode(server) do
    GenServer.call(server, :mode)
  end

  @spec supported_modes() :: [atom(), ...]
  def supported_modes, do: Conversation.supported_modes()

  @spec supported_mode_metadata(keyword()) :: [Jido.Conversation.Mode.Registry.mode_metadata()]
  def supported_mode_metadata(opts \\ []) when is_list(opts) do
    Conversation.supported_mode_metadata(opts)
  end

  @spec send_user_message(GenServer.server(), String.t(), keyword()) ::
          {:ok, Conversation.t(), [struct()]} | {:error, term()}
  def send_user_message(server, content, opts \\ []) when is_binary(content) and is_list(opts) do
    GenServer.call(server, {:send_user_message, content, opts})
  end

  @spec record_assistant_message(GenServer.server(), String.t(), keyword()) ::
          {:ok, Conversation.t(), [struct()]} | {:error, term()}
  def record_assistant_message(server, content, opts \\ [])
      when is_binary(content) and is_list(opts) do
    GenServer.call(server, {:record_assistant_message, content, opts})
  end

  @spec configure_llm(GenServer.server(), atom(), keyword()) ::
          {:ok, Conversation.t(), [struct()]} | {:error, term()}
  def configure_llm(server, backend, opts \\ []) when is_atom(backend) and is_list(opts) do
    GenServer.call(server, {:configure_llm, backend, opts})
  end

  @spec configure_skills(GenServer.server(), [String.t() | atom()]) ::
          {:ok, Conversation.t(), [struct()]} | {:error, term()}
  def configure_skills(server, enabled) when is_list(enabled) do
    GenServer.call(server, {:configure_skills, enabled})
  end

  @spec configure_mode(GenServer.server(), atom(), keyword()) ::
          {:ok, Conversation.t(), [struct()]} | {:error, term()}
  def configure_mode(server, mode, opts \\ []) when is_atom(mode) and is_list(opts) do
    GenServer.call(server, {:configure_mode, mode, opts})
  end

  @spec generate_assistant_reply(GenServer.server(), keyword()) ::
          {:ok, reference()} | {:error, :generation_in_progress}
  def generate_assistant_reply(server, opts \\ []) when is_list(opts) do
    GenServer.call(server, {:generate_assistant_reply, opts})
  end

  @spec cancel_generation(GenServer.server(), String.t()) ::
          :ok | {:error, :no_generation_in_progress}
  def cancel_generation(server, reason \\ "cancel_requested") when is_binary(reason) do
    GenServer.call(server, {:cancel_generation, reason})
  end

  @impl true
  def init(conversation_opts) do
    {:ok, %{conversation: Conversation.new(conversation_opts), active_generation: nil}}
  end

  @impl true
  def handle_call(:conversation, _from, state) do
    {:reply, state.conversation, state}
  end

  @impl true
  def handle_call(:derived_state, _from, state) do
    {:reply, Conversation.derived_state(state.conversation), state}
  end

  @impl true
  def handle_call({:llm_context, opts}, _from, state) do
    {:reply, Conversation.llm_context(state.conversation, opts), state}
  end

  @impl true
  def handle_call(:mode, _from, state) do
    {:reply, Conversation.mode(state.conversation), state}
  end

  @impl true
  def handle_call(:timeline, _from, state) do
    {:reply, Conversation.timeline(state.conversation), state}
  end

  @impl true
  def handle_call(:thread, _from, state) do
    {:reply, Conversation.thread(state.conversation), state}
  end

  @impl true
  def handle_call({:messages, opts}, _from, state) do
    {:reply, Conversation.messages(state.conversation, opts), state}
  end

  @impl true
  def handle_call(:thread_entries, _from, state) do
    {:reply, Conversation.thread_entries(state.conversation), state}
  end

  @impl true
  def handle_call({:send_user_message, _content, _opts}, _from, %{active_generation: %{}} = state) do
    {:reply, {:error, :generation_in_progress}, state}
  end

  @impl true
  def handle_call({:send_user_message, content, opts}, _from, state) do
    case Conversation.send_user_message(state.conversation, content, opts) do
      {:ok, conversation, directives} ->
        {:reply, {:ok, conversation, directives}, %{state | conversation: conversation}}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(
        {:record_assistant_message, _content, _opts},
        _from,
        %{active_generation: %{}} = state
      ) do
    {:reply, {:error, :generation_in_progress}, state}
  end

  @impl true
  def handle_call({:record_assistant_message, content, opts}, _from, state) do
    case Conversation.record_assistant_message(state.conversation, content, opts) do
      {:ok, conversation, directives} ->
        {:reply, {:ok, conversation, directives}, %{state | conversation: conversation}}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:configure_llm, _backend, _opts}, _from, %{active_generation: %{}} = state) do
    {:reply, {:error, :generation_in_progress}, state}
  end

  @impl true
  def handle_call({:configure_llm, backend, opts}, _from, state) do
    {:ok, conversation, directives} =
      Conversation.configure_llm(state.conversation, backend, opts)

    {:reply, {:ok, conversation, directives}, %{state | conversation: conversation}}
  end

  @impl true
  def handle_call({:configure_skills, _enabled}, _from, %{active_generation: %{}} = state) do
    {:reply, {:error, :generation_in_progress}, state}
  end

  @impl true
  def handle_call({:configure_skills, enabled}, _from, state) do
    {:ok, conversation, directives} =
      Conversation.configure_skills(state.conversation, enabled)

    {:reply, {:ok, conversation, directives}, %{state | conversation: conversation}}
  end

  @impl true
  def handle_call({:configure_mode, mode, opts}, _from, state) do
    cause_id = Keyword.get(opts, :cause_id, Jido.Util.generate_id())
    opts = Keyword.put_new(opts, :cause_id, cause_id)

    if state.active_generation do
      handle_configure_mode_while_running(state, mode, opts)
    else
      handle_configure_mode_idle(state, mode, opts, cause_id)
    end
  end

  @impl true
  def handle_call({:generate_assistant_reply, _opts}, _from, %{active_generation: %{}} = state) do
    {:reply, {:error, :generation_in_progress}, state}
  end

  @impl true
  def handle_call({:generate_assistant_reply, opts}, {reply_to, _tag}, state) do
    generation_ref = make_ref()
    conversation = state.conversation

    task =
      Task.async(fn ->
        Conversation.generate_assistant_reply(conversation, opts)
      end)

    active_generation = %{task: task, generation_ref: generation_ref, reply_to: reply_to}

    {:reply, {:ok, generation_ref}, %{state | active_generation: active_generation}}
  end

  @impl true
  def handle_call({:cancel_generation, _reason}, _from, %{active_generation: nil} = state) do
    {:reply, {:error, :no_generation_in_progress}, state}
  end

  @impl true
  def handle_call({:cancel_generation, reason}, _from, %{active_generation: active} = state) do
    _ = Task.shutdown(active.task, :brutal_kill)
    Process.demonitor(active.task.ref, [:flush])

    {:ok, conversation, _directives} =
      Conversation.cancel(state.conversation, reason)

    notify(active.reply_to, {:generation_canceled, active.generation_ref, reason})

    {:reply, :ok, %{state | conversation: conversation, active_generation: nil}}
  end

  @impl true
  def handle_info(
        {task_ref, result},
        %{active_generation: %{task: %Task{ref: task_ref}} = active} = state
      ) do
    Process.demonitor(task_ref, [:flush])

    case result do
      {:ok, conversation, llm_result} ->
        notify(active.reply_to, {:generation_result, active.generation_ref, {:ok, llm_result}})

        {:noreply, %{state | conversation: conversation, active_generation: nil}}

      {:error, %LLMError{} = error} ->
        notify(active.reply_to, {:generation_result, active.generation_ref, {:error, error}})

        {:noreply, %{state | active_generation: nil}}

      {:error, reason} ->
        error = LLMError.from_reason(reason, :unknown, message: "generation failed")
        notify(active.reply_to, {:generation_result, active.generation_ref, {:error, error}})

        {:noreply, %{state | active_generation: nil}}
    end
  end

  @impl true
  def handle_info(
        {:DOWN, task_ref, :process, _pid, reason},
        %{active_generation: %{task: %Task{ref: task_ref}} = active} = state
      ) do
    error = LLMError.from_reason(reason, :unknown, message: "generation task crashed")
    notify(active.reply_to, {:generation_result, active.generation_ref, {:error, error}})
    {:noreply, %{state | active_generation: nil}}
  end

  @impl true
  def handle_info(_message, state), do: {:noreply, state}

  defp handle_configure_mode_idle(state, mode, opts, cause_id) do
    case Conversation.configure_mode(state.conversation, mode, opts) do
      {:ok, conversation, directives} ->
        {:reply, {:ok, conversation, directives}, %{state | conversation: conversation}}

      {:error, reason} ->
        rejection_reason = switch_rejection_reason(reason)

        conversation =
          Conversation.audit_mode_switch(state.conversation, :rejected, %{
            from_mode: Conversation.mode(state.conversation),
            to_mode: mode,
            reason: rejection_reason,
            cause_id: cause_id
          })

        {:reply, {:error, reason}, %{state | conversation: conversation}}
    end
  end

  defp handle_configure_mode_while_running(state, mode, opts) do
    force_switch? = Keyword.get(opts, :force, false)
    cause_id = Keyword.get(opts, :cause_id, Jido.Util.generate_id())

    if force_switch? do
      handle_forced_mode_switch(state, mode, opts, cause_id)
    else
      conversation =
        Conversation.audit_mode_switch(state.conversation, :rejected, %{
          from_mode: Conversation.mode(state.conversation),
          to_mode: mode,
          reason: "run_in_progress",
          cause_id: cause_id
        })

      {:reply, {:error, :run_in_progress}, %{state | conversation: conversation}}
    end
  end

  defp handle_forced_mode_switch(state, mode, opts, cause_id) do
    cancel_reason =
      opts
      |> Keyword.get(:cancel_reason, "")
      |> normalize_cancel_reason()

    if cancel_reason == nil do
      conversation =
        Conversation.audit_mode_switch(state.conversation, :rejected, %{
          from_mode: Conversation.mode(state.conversation),
          to_mode: mode,
          reason: "force_cancel_reason_required",
          cause_id: cause_id
        })

      {:reply, {:error, :force_cancel_reason_required}, %{state | conversation: conversation}}
    else
      active = state.active_generation
      _ = Task.shutdown(active.task, :brutal_kill)
      Process.demonitor(active.task.ref, [:flush])

      {:ok, canceled_conversation, _directives} =
        Conversation.cancel(state.conversation, cancel_reason)

      notify(active.reply_to, {:generation_canceled, active.generation_ref, cancel_reason})

      mode_opts =
        opts
        |> Keyword.delete(:force)
        |> Keyword.delete(:cancel_reason)
        |> Keyword.put_new(:reason, "forced_mode_switch")

      case Conversation.configure_mode(canceled_conversation, mode, mode_opts) do
        {:ok, conversation, directives} ->
          {:reply, {:ok, conversation, directives},
           %{state | conversation: conversation, active_generation: nil}}

        {:error, reason} ->
          conversation =
            Conversation.audit_mode_switch(canceled_conversation, :rejected, %{
              from_mode: Conversation.mode(canceled_conversation),
              to_mode: mode,
              reason: switch_rejection_reason(reason),
              cause_id: cause_id
            })

          {:reply, {:error, reason},
           %{state | conversation: conversation, active_generation: nil}}
      end
    end
  end

  defp normalize_cancel_reason(reason) when is_binary(reason) do
    trimmed = String.trim(reason)
    if trimmed == "", do: nil, else: trimmed
  end

  defp normalize_cancel_reason(_reason), do: nil

  defp switch_rejection_reason(reason) when is_atom(reason), do: Atom.to_string(reason)

  defp switch_rejection_reason({reason, _details}) when is_atom(reason),
    do: Atom.to_string(reason)

  defp switch_rejection_reason({reason, _, _}) when is_atom(reason), do: Atom.to_string(reason)

  defp notify(reply_to, payload) when is_pid(reply_to) do
    send(reply_to, {:jido_conversation, payload})
  end
end
