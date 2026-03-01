defmodule Jido.Conversation.Mode.Run do
  @moduledoc """
  Shared mode-run status and transition contracts.
  """

  @terminal_statuses [:completed, :failed, :canceled]

  @status_transitions %{
    pending: [:running, :failed, :canceled],
    running: [:interrupted, :completed, :failed, :canceled],
    interrupted: [:running, :failed, :canceled],
    completed: [],
    failed: [],
    canceled: []
  }
  @status_from_string %{
    "pending" => :pending,
    "running" => :running,
    "interrupted" => :interrupted,
    "completed" => :completed,
    "failed" => :failed,
    "canceled" => :canceled
  }
  @statuses Map.keys(@status_transitions)
  @modes_from_string %{
    "coding" => :coding,
    "planning" => :planning,
    "engineering" => :engineering
  }

  @type status :: :pending | :running | :interrupted | :completed | :failed | :canceled

  @type snapshot :: %{
          required(:run_id) => String.t(),
          required(:mode) => atom(),
          required(:status) => status(),
          required(:step_id) => String.t() | nil,
          required(:reason) => String.t() | nil,
          optional(:started_at) => integer() | nil,
          optional(:updated_at) => integer() | nil,
          optional(:metadata) => map()
        }

  def statuses do
    @statuses
  end

  def terminal_statuses, do: @terminal_statuses

  def transition_matrix, do: @status_transitions

  @spec allowed_transition?(status(), status()) :: boolean()
  def allowed_transition?(from, to) when from in @statuses and to in @statuses do
    to in Map.fetch!(@status_transitions, from)
  end

  def allowed_transition?(_from, _to), do: false

  @spec serialize_snapshot(map()) :: snapshot() | nil
  def serialize_snapshot(snapshot) when is_map(snapshot) do
    with {:ok, run_id} <- fetch_nonblank(snapshot, :run_id),
         {:ok, mode} <- fetch_mode(snapshot),
         {:ok, status} <- fetch_status(snapshot) do
      %{
        run_id: run_id,
        mode: mode,
        status: status,
        step_id: optional_nonblank(snapshot, :step_id),
        reason: optional_nonblank(snapshot, :reason),
        started_at: optional_integer(snapshot, :started_at),
        updated_at: optional_integer(snapshot, :updated_at),
        metadata: optional_map(snapshot, :metadata)
      }
    else
      _error -> nil
    end
  end

  def serialize_snapshot(_snapshot), do: nil

  defp fetch_nonblank(map, key) do
    case value_for(map, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _other -> {:error, :invalid}
    end
  end

  defp fetch_mode(map) do
    mode =
      case value_for(map, :mode) do
        value when is_atom(value) -> value
        value when is_binary(value) -> Map.get(@modes_from_string, value)
        _other -> nil
      end

    if is_atom(mode), do: {:ok, mode}, else: {:error, :invalid}
  end

  defp fetch_status(map) do
    status =
      case value_for(map, :status) do
        value when is_atom(value) -> value
        value when is_binary(value) -> Map.get(@status_from_string, value)
        _other -> nil
      end

    if status in statuses(), do: {:ok, status}, else: {:error, :invalid}
  end

  defp optional_nonblank(map, key) do
    case value_for(map, key) do
      value when is_binary(value) and value != "" -> value
      _other -> nil
    end
  end

  defp optional_integer(map, key) do
    case value_for(map, key) do
      value when is_integer(value) -> value
      _other -> nil
    end
  end

  defp optional_map(map, key) do
    case value_for(map, key) do
      value when is_map(value) -> value
      _other -> %{}
    end
  end

  defp value_for(map, key) do
    Map.get(map, key) || Map.get(map, to_string(key))
  end
end
