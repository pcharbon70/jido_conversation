defmodule Jido.Conversation.Mode.Signal do
  @moduledoc """
  Contract helpers for mode lifecycle and mode control signals.

  Required lifecycle fields:
  - `mode`
  - `run_id`
  - `step_id`
  - `status`
  - `reason`
  - `cause_id`

  Required control fields:
  - `mode`
  - `run_id`
  - `action`
  - `reason`
  - `cause_id`
  """

  alias Jido.Conversation.Mode.Run
  alias Jido.Signal

  @required_contract_major 1
  @lifecycle_prefixes ["conv.in.mode.", "conv.out.mode."]
  @control_prefixes ["conv.in.control.mode."]
  @lifecycle_fields [:mode, :run_id, :step_id, :status, :reason, :cause_id]
  @control_fields [:mode, :run_id, :action, :reason, :cause_id]
  @control_actions [:interrupt, :resume, :cancel]

  @type validation_error ::
          {:type, :not_mode_signal}
          | {:contract_major, :missing | {:unsupported, term()}}
          | {:payload, {:not_map, term()} | {:missing_keys, [atom()]}}
          | {:payload, {:invalid_status, term()} | {:invalid_action, term()}}

  def lifecycle_fields, do: @lifecycle_fields

  def control_fields, do: @control_fields

  @spec mode_lifecycle_type?(String.t()) :: boolean()
  def mode_lifecycle_type?(type) when is_binary(type) do
    Enum.any?(@lifecycle_prefixes, &String.starts_with?(type, &1))
  end

  @spec mode_control_type?(String.t()) :: boolean()
  def mode_control_type?(type) when is_binary(type) do
    Enum.any?(@control_prefixes, &String.starts_with?(type, &1))
  end

  @spec validate(Signal.t()) :: :ok | {:error, validation_error()}
  def validate(%Signal{} = signal) do
    cond do
      mode_lifecycle_type?(signal.type) ->
        with :ok <- validate_contract_major(signal),
             :ok <- validate_required_keys(signal.data, @lifecycle_fields) do
          validate_status(value_for(signal.data, :status))
        end

      mode_control_type?(signal.type) ->
        with :ok <- validate_contract_major(signal),
             :ok <- validate_required_keys(signal.data, @control_fields) do
          validate_action(value_for(signal.data, :action))
        end

      true ->
        {:error, {:type, :not_mode_signal}}
    end
  end

  defp validate_contract_major(%Signal{} = signal) do
    extensions = signal.extensions || %{}
    major = value_for(extensions, :contract_major)

    cond do
      is_nil(major) -> {:error, {:contract_major, :missing}}
      major == @required_contract_major -> :ok
      true -> {:error, {:contract_major, {:unsupported, major}}}
    end
  end

  defp validate_required_keys(payload, required_keys) when is_map(payload) do
    missing =
      Enum.reject(required_keys, fn key ->
        Map.has_key?(payload, key) || Map.has_key?(payload, to_string(key))
      end)

    case missing do
      [] -> :ok
      _ -> {:error, {:payload, {:missing_keys, missing}}}
    end
  end

  defp validate_required_keys(payload, _required_keys),
    do: {:error, {:payload, {:not_map, payload}}}

  defp validate_status(status) when is_atom(status) do
    if status in Run.statuses() do
      :ok
    else
      {:error, {:payload, {:invalid_status, status}}}
    end
  end

  defp validate_status(status) when is_binary(status) do
    if status in Enum.map(Run.statuses(), &Atom.to_string/1) do
      :ok
    else
      {:error, {:payload, {:invalid_status, status}}}
    end
  end

  defp validate_status(status), do: {:error, {:payload, {:invalid_status, status}}}

  defp validate_action(action) when is_atom(action) and action in @control_actions, do: :ok

  defp validate_action(action) when is_binary(action) do
    if action in Enum.map(@control_actions, &Atom.to_string/1) do
      :ok
    else
      {:error, {:payload, {:invalid_action, action}}}
    end
  end

  defp validate_action(action), do: {:error, {:payload, {:invalid_action, action}}}

  defp value_for(map, key) do
    Map.get(map, key) || Map.get(map, to_string(key))
  end
end
