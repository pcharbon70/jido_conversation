defmodule JidoConversation.Ingest.Pipeline do
  @moduledoc """
  Journal-first ingestion pipeline.

  Ingestion flow:
  1. Normalize and validate event contract
  2. Deduplicate by `{subject, signal_id}`
  3. Append to journal (with optional `cause_id`)
  4. Publish to the bus
  """

  use GenServer

  require Logger

  alias Jido.Signal
  alias Jido.Signal.Bus
  alias Jido.Signal.Bus.RecordedSignal
  alias Jido.Signal.Journal
  alias JidoConversation.Config
  alias JidoConversation.Signal.Contract

  @type dedupe_key :: {String.t(), String.t()}
  @type ingest_status :: :published | :duplicate

  @type ingest_result :: %{
          signal: Signal.t(),
          status: ingest_status(),
          recorded: [RecordedSignal.t()]
        }

  @type ingest_error ::
          {:invalid_cause_id, term()}
          | {:contract_invalid, term()}
          | {:journal_record_failed, term()}
          | {:publish_failed, term()}

  @type state :: %{
          bus_name: atom(),
          dedupe: %{dedupe_key() => :published | :journaled},
          dedupe_limit: pos_integer(),
          dedupe_queue: :queue.queue(dedupe_key()),
          journal: Journal.t()
        }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec ingest(Contract.input(), keyword()) :: {:ok, ingest_result()} | {:error, ingest_error()}
  def ingest(attrs, opts \\ []) do
    GenServer.call(__MODULE__, {:ingest, attrs, opts})
  end

  @spec conversation_events(String.t()) :: [Signal.t()]
  def conversation_events(conversation_id) when is_binary(conversation_id) do
    GenServer.call(__MODULE__, {:conversation_events, conversation_id})
  end

  @spec trace_chain(String.t(), :forward | :backward) :: [Signal.t()]
  def trace_chain(signal_id, direction \\ :forward)

  def trace_chain(signal_id, direction)
      when is_binary(signal_id) and direction in [:forward, :backward] do
    GenServer.call(__MODULE__, {:trace_chain, signal_id, direction})
  end

  @spec replay(String.t(), non_neg_integer(), keyword()) ::
          {:ok, [RecordedSignal.t()]} | {:error, term()}
  def replay(path \\ "conv.**", start_timestamp \\ 0, opts \\ [])

  def replay(path, start_timestamp, opts)
      when is_binary(path) and is_integer(start_timestamp) and start_timestamp >= 0 and
             is_list(opts) do
    GenServer.call(__MODULE__, {:replay, path, start_timestamp, opts})
  end

  @spec dedupe_size() :: non_neg_integer()
  def dedupe_size do
    GenServer.call(__MODULE__, :dedupe_size)
  end

  @impl true
  def init(_opts) do
    journal = init_journal(Config.journal_adapter())

    {:ok,
     %{
       bus_name: Config.bus_name(),
       journal: journal,
       dedupe: %{},
       dedupe_queue: :queue.new(),
       dedupe_limit: Config.ingestion_dedupe_cache_size()
     }}
  end

  @impl true
  def handle_call({:ingest, attrs, opts}, _from, state) do
    case do_ingest(attrs, opts, state) do
      {:ok, result, state} -> {:reply, {:ok, result}, state}
      {:error, reason, state} -> {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:conversation_events, conversation_id}, _from, state) do
    {:reply, Journal.get_conversation(state.journal, conversation_id), state}
  end

  @impl true
  def handle_call({:trace_chain, signal_id, direction}, _from, state) do
    {:reply, Journal.trace_chain(state.journal, signal_id, direction), state}
  end

  @impl true
  def handle_call({:replay, path, start_timestamp, opts}, _from, state) do
    {:reply, Bus.replay(state.bus_name, path, start_timestamp, opts), state}
  end

  @impl true
  def handle_call(:dedupe_size, _from, state) do
    {:reply, map_size(state.dedupe), state}
  end

  defp do_ingest(attrs, opts, state) do
    with {:ok, cause_id} <- normalize_cause_id(opts),
         {:ok, signal} <- normalize_signal(attrs) do
      signal = maybe_attach_cause_id(signal, cause_id)
      key = dedupe_key(signal)

      case Map.get(state.dedupe, key) do
        :published ->
          {:ok, %{signal: signal, status: :duplicate, recorded: []}, state}

        :journaled ->
          publish_journaled(state, signal, key)

        nil ->
          journal_then_publish(state, signal, key, cause_id)
      end
    else
      {:error, reason} -> {:error, reason, state}
    end
  end

  defp normalize_cause_id(opts) when is_list(opts) do
    case Keyword.get(opts, :cause_id) do
      nil ->
        {:ok, nil}

      cause_id when is_binary(cause_id) ->
        if String.trim(cause_id) == "" do
          {:error, {:invalid_cause_id, cause_id}}
        else
          {:ok, cause_id}
        end

      other ->
        {:error, {:invalid_cause_id, other}}
    end
  end

  defp normalize_cause_id(other), do: {:error, {:invalid_cause_id, other}}

  defp normalize_signal(attrs) do
    case Contract.normalize(attrs) do
      {:ok, signal} -> {:ok, signal}
      {:error, reason} -> {:error, {:contract_invalid, reason}}
    end
  end

  defp publish_journaled(state, signal, key) do
    case publish_signal(state.bus_name, signal) do
      {:ok, recorded} ->
        state = put_dedupe(state, key, :published)
        {:ok, %{signal: signal, status: :published, recorded: recorded}, state}

      {:error, reason} ->
        {:error, {:publish_failed, reason}, state}
    end
  end

  defp journal_then_publish(state, signal, key, cause_id) do
    case Journal.record(state.journal, signal, cause_id) do
      {:ok, journal} ->
        state = %{state | journal: journal}
        state = put_dedupe(state, key, :journaled)

        case publish_signal(state.bus_name, signal) do
          {:ok, recorded} ->
            state = put_dedupe(state, key, :published)
            {:ok, %{signal: signal, status: :published, recorded: recorded}, state}

          {:error, reason} ->
            Logger.warning(
              "journaled signal failed to publish id=#{signal.id}: #{inspect(reason)}"
            )

            {:error, {:publish_failed, reason}, state}
        end

      {:error, reason} ->
        {:error, {:journal_record_failed, reason}, state}
    end
  end

  defp publish_signal(bus_name, signal) do
    Bus.publish(bus_name, [signal])
  end

  defp maybe_attach_cause_id(%Signal{} = signal, nil), do: signal

  defp maybe_attach_cause_id(%Signal{} = signal, cause_id) when is_binary(cause_id) do
    extensions = Map.put(signal.extensions, "cause_id", cause_id)
    %{signal | extensions: extensions}
  end

  defp dedupe_key(%Signal{} = signal), do: {signal.subject, signal.id}

  defp put_dedupe(state, key, status) do
    is_new_key = not Map.has_key?(state.dedupe, key)

    dedupe = Map.put(state.dedupe, key, status)
    queue = if is_new_key, do: :queue.in(key, state.dedupe_queue), else: state.dedupe_queue

    %{state | dedupe: dedupe, dedupe_queue: queue}
    |> enforce_dedupe_limit()
  end

  defp enforce_dedupe_limit(%{dedupe_limit: limit} = state) when map_size(state.dedupe) <= limit,
    do: state

  defp enforce_dedupe_limit(state) do
    case :queue.out(state.dedupe_queue) do
      {{:value, oldest_key}, queue} ->
        state
        |> Map.put(:dedupe_queue, queue)
        |> Map.put(:dedupe, Map.delete(state.dedupe, oldest_key))
        |> enforce_dedupe_limit()

      {:empty, _queue} ->
        state
    end
  end

  defp init_journal(adapter) when is_atom(adapter), do: Journal.new(adapter)
end
