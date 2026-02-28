defmodule Jido.Conversation.Runtime do
  @moduledoc """
  Managed runtime API for starting and controlling conversation server processes.
  """

  alias Jido.Conversation.Server
  alias JidoConversation.ConversationRef

  @registry_name Jido.Conversation.Registry
  @server_supervisor_name Jido.Conversation.ServerSupervisor

  @type locator :: String.t() | {String.t(), String.t()}

  @type ensure_status :: :started | :existing

  @spec start_conversation(keyword() | map()) :: {:ok, pid()} | {:error, term()}
  def start_conversation(opts) do
    with {:ok, key, server_opts} <- normalize_start_opts(opts) do
      start_child(key, server_opts)
    end
  end

  @spec ensure_conversation(keyword() | map()) :: {:ok, pid(), ensure_status()} | {:error, term()}
  def ensure_conversation(opts) do
    with {:ok, key, server_opts} <- normalize_start_opts(opts) do
      ensure_started(key, server_opts)
    end
  end

  @spec whereis(locator()) :: pid() | nil
  def whereis(locator) do
    case locator_to_key(locator) do
      {:ok, key} -> whereis_key(key)
      {:error, _reason} -> nil
    end
  end

  @spec stop_conversation(locator()) :: :ok | {:error, :not_found | term()}
  def stop_conversation(locator) do
    with {:ok, key} <- locator_to_key(locator),
         pid when is_pid(pid) <- whereis_key(key),
         :ok <- DynamicSupervisor.terminate_child(@server_supervisor_name, pid) do
      await_stopped(key, 20)
    else
      nil ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec via_name(String.t()) :: {:via, Registry, {module(), String.t()}}
  def via_name(conversation_id) when is_binary(conversation_id) do
    key = conversation_key(conversation_id)
    {:via, Registry, {@registry_name, key}}
  end

  @spec via_name(String.t(), String.t()) :: {:via, Registry, {module(), String.t()}}
  def via_name(project_id, conversation_id)
      when is_binary(project_id) and is_binary(conversation_id) do
    {:via, Registry, {@registry_name, project_key(project_id, conversation_id)}}
  end

  defp start_child(key, server_opts) do
    name = {:via, Registry, {@registry_name, key}}

    case DynamicSupervisor.start_child(
           @server_supervisor_name,
           {Server, Keyword.put(server_opts, :name, name)}
         ) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:error, {:already_started, pid}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp ensure_started(key, server_opts) do
    case whereis_key(key) do
      nil -> start_or_existing(key, server_opts)
      pid when is_pid(pid) -> {:ok, pid, :existing}
    end
  end

  defp start_or_existing(key, server_opts) do
    case start_child(key, server_opts) do
      {:ok, pid} -> {:ok, pid, :started}
      {:error, {:already_started, pid}} -> {:ok, pid, :existing}
      {:error, reason} -> {:error, reason}
    end
  end

  defp whereis_key(key) do
    case Registry.lookup(@registry_name, key) do
      [{pid, _value} | _] -> pid
      [] -> nil
    end
  end

  defp await_stopped(key, retries) when is_integer(retries) and retries > 0 do
    case whereis_key(key) do
      nil ->
        :ok

      _pid ->
        Process.sleep(10)
        await_stopped(key, retries - 1)
    end
  end

  defp await_stopped(_key, _retries), do: :ok

  defp normalize_start_opts(opts) do
    opts_map = normalize_opts(opts)

    conversation_id = opts_map[:conversation_id] || opts_map[:id]
    project_id = opts_map[:project_id]

    with :ok <- validate_id(conversation_id, :conversation_id),
         :ok <- validate_optional_id(project_id, :project_id),
         {:ok, metadata} <- normalize_metadata(opts_map[:metadata], project_id),
         {:ok, state} <- normalize_state(opts_map[:state]),
         key <- key_for(project_id, conversation_id) do
      server_opts =
        []
        |> Keyword.put(:conversation_id, conversation_id)
        |> Keyword.put(:metadata, metadata)
        |> maybe_put_keyword(:state, state)

      {:ok, key, server_opts}
    end
  end

  defp key_for(nil, conversation_id), do: conversation_key(conversation_id)
  defp key_for(project_id, conversation_id), do: project_key(project_id, conversation_id)

  defp conversation_key(conversation_id),
    do: "conversation/" <> URI.encode_www_form(conversation_id)

  defp project_key(project_id, conversation_id) do
    ConversationRef.subject(project_id, conversation_id)
  end

  defp locator_to_key({project_id, conversation_id})
       when is_binary(project_id) and is_binary(conversation_id) do
    if valid_nonblank?(project_id) and valid_nonblank?(conversation_id) do
      {:ok, project_key(project_id, conversation_id)}
    else
      {:error, :invalid_locator}
    end
  end

  defp locator_to_key(conversation_id) when is_binary(conversation_id) do
    if valid_nonblank?(conversation_id) do
      {:ok, conversation_key(conversation_id)}
    else
      {:error, :invalid_locator}
    end
  end

  defp locator_to_key(_), do: {:error, :invalid_locator}

  defp normalize_opts(opts) when is_list(opts), do: Map.new(opts)
  defp normalize_opts(opts) when is_map(opts), do: opts
  defp normalize_opts(_), do: %{}

  defp normalize_metadata(nil, project_id) do
    {:ok, maybe_put_map(%{}, :project_id, project_id)}
  end

  defp normalize_metadata(metadata, project_id) when is_map(metadata) do
    {:ok, maybe_put_map(metadata, :project_id, project_id)}
  end

  defp normalize_metadata(_metadata, _project_id),
    do: {:error, {:invalid_metadata, :expected_map}}

  defp normalize_state(nil), do: {:ok, nil}
  defp normalize_state(state) when is_map(state), do: {:ok, state}
  defp normalize_state(_state), do: {:error, {:invalid_state, :expected_map}}

  defp validate_id(value, field) when is_binary(value) do
    if valid_nonblank?(value), do: :ok, else: {:error, {field, :blank}}
  end

  defp validate_id(_value, field), do: {:error, {field, :missing}}

  defp validate_optional_id(nil, _field), do: :ok

  defp validate_optional_id(value, field) when is_binary(value) do
    if valid_nonblank?(value), do: :ok, else: {:error, {field, :blank}}
  end

  defp validate_optional_id(_value, field), do: {:error, {field, :invalid}}

  defp valid_nonblank?(value) when is_binary(value), do: String.trim(value) != ""

  defp maybe_put_map(map, _key, nil), do: map
  defp maybe_put_map(map, key, value), do: Map.put(map, key, value)

  defp maybe_put_keyword(keyword, _key, nil), do: keyword
  defp maybe_put_keyword(keyword, key, value), do: Keyword.put(keyword, key, value)
end
