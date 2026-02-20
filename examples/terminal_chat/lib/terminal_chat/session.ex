defmodule TerminalChat.Session do
  @moduledoc """
  Conversation session process with one cancellable in-flight request.
  """

  use GenServer

  require Logger

  alias TerminalChat.LLMClient
  alias TerminalChat.WebSearch

  @type role :: :system | :user | :assistant | :tool

  @type message :: %{
          role: role(),
          content: String.t(),
          at: DateTime.t()
        }

  @type active_request :: %{
          task: Task.t(),
          type: :chat | :search,
          reply_to: pid()
        }

  @type state :: %{
          history: [message()],
          active: active_request() | nil
        }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec history() :: [message()]
  def history do
    GenServer.call(__MODULE__, :history)
  end

  @spec submit_message(String.t(), pid()) :: :ok
  def submit_message(text, reply_to) when is_binary(text) and is_pid(reply_to) do
    GenServer.cast(__MODULE__, {:submit_message, text, reply_to})
  end

  @spec search(String.t(), pid()) :: :ok
  def search(query, reply_to) when is_binary(query) and is_pid(reply_to) do
    GenServer.cast(__MODULE__, {:search, query, reply_to})
  end

  @spec cancel(pid()) :: :ok
  def cancel(reply_to) when is_pid(reply_to) do
    GenServer.cast(__MODULE__, {:cancel, reply_to})
  end

  @impl true
  def init(_opts) do
    {:ok, %{history: [], active: nil}}
  end

  @impl true
  def handle_call(:history, _from, state) do
    {:reply, state.history, state}
  end

  @impl true
  def handle_cast({:submit_message, text, reply_to}, state) do
    text = String.trim(text)

    cond do
      text == "" ->
        {:noreply, state}

      state.active != nil ->
        notify(reply_to, {:status, "Request already in flight. Use /cancel first."})
        {:noreply, state}

      true ->
        state =
          state
          |> append_message(:user, text)
          |> start_chat_task(reply_to)

        {:noreply, state}
    end
  end

  @impl true
  def handle_cast({:search, query, reply_to}, state) do
    query = String.trim(query)

    cond do
      query == "" ->
        notify(reply_to, {:status, "Usage: /search <query>"})
        {:noreply, state}

      state.active != nil ->
        notify(reply_to, {:status, "Request already in flight. Use /cancel first."})
        {:noreply, state}

      true ->
        state =
          state
          |> append_message(:user, "/search #{query}")
          |> start_search_task(query, reply_to)

        {:noreply, state}
    end
  end

  @impl true
  def handle_cast({:cancel, reply_to}, %{active: nil} = state) do
    notify(reply_to, {:status, "No active request to cancel."})
    {:noreply, state}
  end

  @impl true
  def handle_cast({:cancel, reply_to}, %{active: active} = state) do
    _ = Task.shutdown(active.task, :brutal_kill)
    Process.demonitor(active.task.ref, [:flush])

    state =
      state
      |> Map.put(:active, nil)
      |> append_message(:tool, "Canceled #{active.type} request.")

    notify(reply_to, :history_changed)
    notify(reply_to, {:status, "Canceled active request."})

    {:noreply, state}
  end

  @impl true
  def handle_info({ref, result}, %{active: %{task: %Task{ref: ref}} = active} = state) do
    Process.demonitor(ref, [:flush])

    state =
      state
      |> apply_task_result(result)
      |> Map.put(:active, nil)

    notify(active.reply_to, :history_changed)
    notify(active.reply_to, {:status, "Ready."})

    {:noreply, state}
  end

  @impl true
  def handle_info(
        {:DOWN, ref, :process, _pid, reason},
        %{active: %{task: %Task{ref: ref}} = active} = state
      ) do
    Logger.error("request task crashed: #{inspect(reason)}")

    state =
      state
      |> append_message(:tool, "Request failed: #{inspect(reason)}")
      |> Map.put(:active, nil)

    notify(active.reply_to, :history_changed)
    notify(active.reply_to, {:status, "Request failed."})

    {:noreply, state}
  end

  @impl true
  def handle_info(_message, state) do
    {:noreply, state}
  end

  defp start_chat_task(state, reply_to) do
    notify(reply_to, :history_changed)
    notify(reply_to, {:status, "Waiting for LLM response..."})

    history = state.history

    task =
      Task.Supervisor.async_nolink(TerminalChat.TaskSupervisor, fn ->
        with {:ok, %{content: content, model: model}} <- LLMClient.chat(history) do
          {:ok, {:chat, content, model}}
        end
      end)

    %{state | active: %{task: task, type: :chat, reply_to: reply_to}}
  end

  defp start_search_task(state, query, reply_to) do
    notify(reply_to, :history_changed)
    notify(reply_to, {:status, "Running web search..."})

    history = state.history

    task =
      Task.Supervisor.async_nolink(TerminalChat.TaskSupervisor, fn ->
        with {:ok, results} <- WebSearch.search(query) do
          tool_text = WebSearch.format_results(results)
          summary_result = LLMClient.summarize_search(history, query, tool_text)

          case summary_result do
            {:ok, %{content: content, model: model}} ->
              {:ok, {:search, tool_text, content, model}}

            {:error, :missing_anthropic_api_key} ->
              fallback = "Search results:\n#{tool_text}"
              {:ok, {:search, tool_text, fallback, "none"}}

            {:error, _reason} ->
              fallback = "Search results:\n#{tool_text}"
              {:ok, {:search, tool_text, fallback, "none"}}
          end
        end
      end)

    %{state | active: %{task: task, type: :search, reply_to: reply_to}}
  end

  defp apply_task_result(state, {:ok, {:chat, content, model}}) do
    append_message(state, :assistant, "#{content}\n\n(model: #{model})")
  end

  defp apply_task_result(state, {:ok, {:search, tool_text, assistant_text, model}}) do
    state
    |> append_message(:tool, tool_text)
    |> append_message(:assistant, "#{assistant_text}\n\n(model: #{model})")
  end

  defp apply_task_result(state, {:error, :missing_anthropic_api_key}) do
    append_message(
      state,
      :tool,
      "ANTHROPIC_API_KEY is not set. Set it before sending chat prompts."
    )
  end

  defp apply_task_result(state, {:error, :no_results}) do
    append_message(state, :tool, "No search results found.")
  end

  defp apply_task_result(state, {:error, reason}) do
    append_message(state, :tool, "Request failed: #{inspect(reason)}")
  end

  defp append_message(state, role, content)
       when role in [:system, :user, :assistant, :tool] and is_binary(content) do
    message = %{
      role: role,
      content: content,
      at: DateTime.utc_now()
    }

    update_in(state.history, &(&1 ++ [message]))
  end

  defp notify(pid, payload) when is_pid(pid) do
    send(pid, {:terminal_chat, payload})
  end
end
