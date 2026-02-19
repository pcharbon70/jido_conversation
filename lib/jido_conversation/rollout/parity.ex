defmodule JidoConversation.Rollout.Parity do
  @moduledoc """
  Tools for comparing event-runtime outputs against a legacy runtime adapter.
  """

  alias Jido.Signal
  alias JidoConversation.Config
  alias JidoConversation.Ingest
  alias JidoConversation.Rollout.Reporter

  @type parity_status :: :match | :mismatch | :legacy_unavailable

  @type parity_report :: %{
          conversation_id: String.t(),
          compared_at: DateTime.t(),
          status: parity_status(),
          adapter: module(),
          event_output_count: non_neg_integer(),
          legacy_output_count: non_neg_integer(),
          missing_in_legacy: non_neg_integer(),
          missing_in_event: non_neg_integer(),
          reason: term() | nil
        }

  @spec compare_conversation(String.t(), keyword()) :: {:ok, parity_report()} | {:error, term()}
  def compare_conversation(conversation_id, opts \\ [])
      when is_binary(conversation_id) and is_list(opts) do
    start_timestamp = Keyword.get(opts, :start_timestamp, 0)
    adapter = Config.rollout_parity() |> Keyword.fetch!(:legacy_adapter)

    with {:ok, event_records} <- Ingest.replay("conv.out.**", start_timestamp) do
      event_outputs =
        event_records
        |> Enum.map(& &1.signal)
        |> Enum.filter(&(&1.subject == conversation_id))
        |> Enum.map(&normalize_output!/1)

      report =
        case adapter.outputs_for_conversation(conversation_id, opts) do
          {:ok, legacy_outputs} ->
            build_parity_report(conversation_id, adapter, event_outputs, legacy_outputs)

          {:error, reason} ->
            %{
              conversation_id: conversation_id,
              compared_at: DateTime.utc_now(),
              status: :legacy_unavailable,
              adapter: adapter,
              event_output_count: length(event_outputs),
              legacy_output_count: 0,
              missing_in_legacy: 0,
              missing_in_event: 0,
              reason: reason
            }
        end

      Reporter.record_parity_report(report)
      {:ok, report}
    end
  end

  defp build_parity_report(conversation_id, adapter, event_outputs, legacy_outputs) do
    normalized_legacy = Enum.map(legacy_outputs, &normalize_output!/1)
    event_counts = multiset_counts(event_outputs)
    legacy_counts = multiset_counts(normalized_legacy)

    missing_in_legacy = count_excess(event_counts, legacy_counts)
    missing_in_event = count_excess(legacy_counts, event_counts)

    %{
      conversation_id: conversation_id,
      compared_at: DateTime.utc_now(),
      status: parity_status(missing_in_legacy, missing_in_event),
      adapter: adapter,
      event_output_count: length(event_outputs),
      legacy_output_count: length(normalized_legacy),
      missing_in_legacy: missing_in_legacy,
      missing_in_event: missing_in_event,
      reason: nil
    }
  end

  defp normalize_output!(%Signal{} = signal) do
    %{
      type: signal.type,
      subject: signal.subject,
      data: normalize_value(signal.data)
    }
  end

  defp normalize_output!(%{type: type} = output) do
    %{
      type: type,
      subject: Map.get(output, :subject) || Map.get(output, "subject"),
      data: normalize_value(Map.get(output, :data) || Map.get(output, "data") || %{})
    }
  end

  defp normalize_output!(other) do
    raise ArgumentError, "unsupported parity output: #{inspect(other)}"
  end

  defp parity_status(0, 0), do: :match
  defp parity_status(_missing_in_legacy, _missing_in_event), do: :mismatch

  defp multiset_counts(outputs) when is_list(outputs) do
    Enum.reduce(outputs, %{}, fn output, acc ->
      key = parity_key(output)
      Map.update(acc, key, 1, &(&1 + 1))
    end)
  end

  defp count_excess(base_counts, compare_counts) do
    Enum.reduce(base_counts, 0, fn {key, count}, total ->
      compare_count = Map.get(compare_counts, key, 0)
      total + max(count - compare_count, 0)
    end)
  end

  defp parity_key(output) do
    output
    |> normalize_value()
    |> :erlang.term_to_binary()
  end

  defp normalize_value(value) when is_map(value) do
    value
    |> Enum.map(fn {key, nested} -> {normalize_key(key), normalize_value(nested)} end)
    |> Enum.sort_by(fn {key, _nested} -> key end)
  end

  defp normalize_value(value) when is_list(value), do: Enum.map(value, &normalize_value/1)

  defp normalize_value(value) when is_struct(value) do
    value
    |> Map.from_struct()
    |> normalize_value()
  end

  defp normalize_value(value), do: value

  defp normalize_key(key) when is_atom(key), do: Atom.to_string(key)
  defp normalize_key(key), do: key
end
