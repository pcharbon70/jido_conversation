defmodule JidoConversation do
  @moduledoc """
  Entry points for the conversation runtime.
  """

  alias Jido.Conversation
  alias Jido.Conversation.Runtime, as: ConversationRuntime
  alias JidoConversation.Health
  alias JidoConversation.Ingest
  alias JidoConversation.LLM.Result, as: LLMResult
  alias JidoConversation.Projections
  alias JidoConversation.Telemetry, as: RuntimeTelemetry

  @type conversation_locator :: ConversationRuntime.locator()

  @doc """
  Returns runtime health details for the signal bus and runtime supervisors.
  """
  @spec health() :: Health.status_map()
  def health do
    Health.status()
  end

  @doc """
  Starts a managed conversation process.
  """
  @spec start_conversation(keyword() | map()) :: {:ok, pid()} | {:error, term()}
  def start_conversation(opts) do
    ConversationRuntime.start_conversation(opts)
  end

  @doc """
  Ensures a managed conversation process exists and returns whether it was started.
  """
  @spec ensure_conversation(keyword() | map()) ::
          {:ok, pid(), ConversationRuntime.ensure_status()} | {:error, term()}
  def ensure_conversation(opts) do
    ConversationRuntime.ensure_conversation(opts)
  end

  @doc """
  Returns the pid for a managed conversation locator, or `nil` when not found.
  """
  @spec whereis_conversation(conversation_locator()) :: pid() | nil
  def whereis_conversation(locator) do
    ConversationRuntime.whereis(locator)
  end

  @doc """
  Stops a managed conversation process.
  """
  @spec stop_conversation(conversation_locator()) :: :ok | {:error, :invalid_locator | :not_found}
  def stop_conversation(locator) do
    ConversationRuntime.stop_conversation(locator)
  end

  @doc """
  Returns the in-memory managed conversation struct for a locator.
  """
  @spec conversation(conversation_locator()) ::
          {:ok, Conversation.t()} | {:error, :invalid_locator | :not_found}
  def conversation(locator) do
    ConversationRuntime.conversation(locator)
  end

  @doc """
  Returns the in-memory derived state for a managed conversation locator.
  """
  @spec derived_state(conversation_locator()) ::
          {:ok, map()} | {:error, :invalid_locator | :not_found}
  def derived_state(locator) do
    ConversationRuntime.derived_state(locator)
  end

  @doc """
  Returns the in-memory timeline from a managed conversation process.

  This is different from `timeline/2`, which reads projection data from the
  journal/event stream.
  """
  @spec conversation_timeline(conversation_locator()) ::
          {:ok, [map()]} | {:error, :invalid_locator | :not_found}
  def conversation_timeline(locator) do
    ConversationRuntime.timeline(locator)
  end

  @doc """
  Returns the in-memory `Jido.Thread` journal struct from a managed conversation process.
  """
  @spec conversation_thread(conversation_locator()) ::
          {:ok, Jido.Thread.t() | nil} | {:error, :invalid_locator | :not_found}
  def conversation_thread(locator) do
    ConversationRuntime.thread(locator)
  end

  @doc """
  Returns append-only in-memory thread journal entries from a managed conversation process.

  This gives direct access to the raw journal used to derive conversation state.
  """
  @spec conversation_thread_entries(conversation_locator()) ::
          {:ok, [Jido.Thread.Entry.t()]} | {:error, :invalid_locator | :not_found}
  def conversation_thread_entries(locator) do
    ConversationRuntime.thread_entries(locator)
  end

  @doc """
  Returns the in-memory LLM context from a managed conversation process.

  This is different from `llm_context/2`, which reads projection data from the
  journal/event stream.
  """
  @spec conversation_llm_context(conversation_locator(), keyword()) ::
          {:ok, [map()]} | {:error, :invalid_locator | :not_found}
  def conversation_llm_context(locator, opts \\ []) when is_list(opts) do
    ConversationRuntime.llm_context(locator, opts)
  end

  @doc """
  Sends a user message through the managed runtime API.

  If the conversation process does not exist yet, it is created automatically.
  """
  @spec send_user_message(conversation_locator(), String.t(), keyword()) ::
          {:ok, Conversation.t(), [struct()]} | {:error, term()}
  def send_user_message(locator, content, opts \\ []) when is_binary(content) and is_list(opts) do
    ConversationRuntime.send_user_message(locator, content, opts)
  end

  @doc """
  Records an assistant message through the managed runtime API.

  If the conversation process does not exist yet, it is created automatically.
  """
  @spec record_assistant_message(conversation_locator(), String.t(), keyword()) ::
          {:ok, Conversation.t(), [struct()]} | {:error, term()}
  def record_assistant_message(locator, content, opts \\ [])
      when is_binary(content) and is_list(opts) do
    ConversationRuntime.record_assistant_message(locator, content, opts)
  end

  @doc """
  Configures backend/provider/model settings for a managed conversation.

  If the conversation process does not exist yet, it is created automatically.
  """
  @spec configure_llm(conversation_locator(), atom(), keyword()) ::
          {:ok, Conversation.t(), [struct()]} | {:error, term()}
  def configure_llm(locator, backend, opts \\ []) when is_atom(backend) and is_list(opts) do
    ConversationRuntime.configure_llm(locator, backend, opts)
  end

  @doc """
  Configures enabled skill identifiers for a managed conversation.

  If the conversation process does not exist yet, it is created automatically.
  """
  @spec configure_skills(conversation_locator(), [String.t() | atom()]) ::
          {:ok, Conversation.t(), [struct()]} | {:error, term()}
  def configure_skills(locator, enabled) when is_list(enabled) do
    ConversationRuntime.configure_skills(locator, enabled)
  end

  @doc """
  Starts asynchronous assistant generation for a managed conversation.

  If the conversation process does not exist yet, it is created automatically.
  """
  @spec generate_assistant_reply(conversation_locator(), keyword()) ::
          {:ok, reference()} | {:error, :invalid_locator | :generation_in_progress | term()}
  def generate_assistant_reply(locator, opts \\ []) when is_list(opts) do
    ConversationRuntime.generate_assistant_reply(locator, opts)
  end

  @doc """
  Requests cancellation of an active generation for a managed conversation.
  """
  @spec cancel_generation(conversation_locator(), String.t()) ::
          :ok | {:error, :invalid_locator | :not_found | :no_generation_in_progress}
  def cancel_generation(locator, reason \\ "cancel_requested") when is_binary(reason) do
    ConversationRuntime.cancel_generation(locator, reason)
  end

  @doc """
  Waits for an in-flight generation result from a managed conversation.

  The caller process must be the same process that started generation.
  """
  @spec await_generation(conversation_locator(), reference(), keyword()) ::
          {:ok, LLMResult.t()} | {:error, :timeout | {:canceled, String.t()} | term()}
  def await_generation(locator, generation_ref, opts \\ [])
      when is_reference(generation_ref) and is_list(opts) do
    timeout_ms = Keyword.get(opts, :timeout_ms, 30_000)
    cancel_on_timeout? = Keyword.get(opts, :cancel_on_timeout?, true)
    cancel_reason = Keyword.get(opts, :cancel_reason, "await_timeout")

    receive do
      {:jido_conversation, {:generation_result, ^generation_ref, {:ok, %LLMResult{} = result}}} ->
        {:ok, result}

      {:jido_conversation, {:generation_result, ^generation_ref, {:error, reason}}} ->
        {:error, reason}

      {:jido_conversation, {:generation_canceled, ^generation_ref, reason}}
      when is_binary(reason) ->
        {:error, {:canceled, reason}}
    after
      timeout_ms ->
        maybe_cancel_on_timeout(locator, cancel_on_timeout?, cancel_reason)
        {:error, :timeout}
    end
  end

  @doc """
  Sends a user message, starts generation, and waits for completion in one call.

  Options:
  - `:message_opts` options for `send_user_message/3`
  - `:generation_opts` options for `generate_assistant_reply/2`
  - `:await_opts` options for `await_generation/3`
  """
  @spec send_and_generate(conversation_locator(), String.t(), keyword()) ::
          {:ok, Conversation.t(), LLMResult.t()} | {:error, term()}
  def send_and_generate(locator, content, opts \\ []) when is_binary(content) and is_list(opts) do
    message_opts = Keyword.get(opts, :message_opts, [])
    generation_opts = Keyword.get(opts, :generation_opts, [])
    await_opts = Keyword.get(opts, :await_opts, [])

    with {:ok, _conversation, _directives} <- send_user_message(locator, content, message_opts),
         {:ok, generation_ref} <- generate_assistant_reply(locator, generation_opts),
         {:ok, result} <- await_generation(locator, generation_ref, await_opts),
         {:ok, conversation} <- conversation(locator) do
      {:ok, conversation, result}
    end
  end

  @doc """
  Ingests an event through the journal-first pipeline.
  """
  @spec ingest(JidoConversation.Signal.Contract.input(), keyword()) ::
          {:ok, JidoConversation.Ingest.Pipeline.ingest_result()}
          | {:error, JidoConversation.Ingest.Pipeline.ingest_error()}
  def ingest(attrs, opts \\ []) do
    Ingest.ingest(attrs, opts)
  end

  @doc """
  Builds a user-facing timeline projection for a conversation.
  """
  @spec timeline(String.t(), keyword()) :: [
          JidoConversation.Projections.Timeline.timeline_entry()
        ]
  def timeline(conversation_id, opts \\ []) do
    Projections.timeline(conversation_id, opts)
  end

  @doc """
  Builds a user-facing timeline projection for a project-scoped conversation.
  """
  @spec timeline(String.t(), String.t(), keyword()) :: [
          JidoConversation.Projections.Timeline.timeline_entry()
        ]
  def timeline(project_id, conversation_id, opts) do
    Projections.timeline(project_id, conversation_id, opts)
  end

  @doc """
  Builds an LLM context projection for a conversation.
  """
  @spec llm_context(String.t(), keyword()) :: [
          JidoConversation.Projections.LlmContext.context_message()
        ]
  def llm_context(conversation_id, opts \\ []) do
    Projections.llm_context(conversation_id, opts)
  end

  @doc """
  Builds an LLM context projection for a project-scoped conversation.
  """
  @spec llm_context(String.t(), String.t(), keyword()) :: [
          JidoConversation.Projections.LlmContext.context_message()
        ]
  def llm_context(project_id, conversation_id, opts) do
    Projections.llm_context(project_id, conversation_id, opts)
  end

  @doc """
  Returns aggregated runtime telemetry metrics.
  """
  @spec telemetry_snapshot() :: JidoConversation.Telemetry.metrics_snapshot()
  def telemetry_snapshot do
    RuntimeTelemetry.snapshot()
  end

  defp maybe_cancel_on_timeout(locator, true, reason) when is_binary(reason) do
    _ = cancel_generation(locator, reason)
    :ok
  end

  defp maybe_cancel_on_timeout(_locator, _cancel_on_timeout?, _reason), do: :ok
end
