defmodule JidoConversation.Ingest.Adapters.Timer do
  @moduledoc """
  Timer/scheduler ingress adapter.
  """

  alias JidoConversation.Ingest

  @spec ingest_tick(String.t(), String.t(), map() | keyword(), keyword()) ::
          {:ok, JidoConversation.Ingest.Pipeline.ingest_result()}
          | {:error, JidoConversation.Ingest.Pipeline.ingest_error()}
  def ingest_tick(conversation_id, tick_id, payload \\ %{}, opts \\ [])
      when is_binary(conversation_id) and is_binary(tick_id) do
    payload = to_map(payload)

    signal = %{
      type: "conv.in.timer.tick",
      source: "/scheduler/timer",
      subject: conversation_id,
      data:
        Map.merge(payload, %{
          message_id: tick_id,
          ingress: "timer"
        }),
      extensions: %{contract_major: 1}
    }

    Ingest.ingest(signal, opts)
  end

  defp to_map(payload) when is_map(payload), do: payload
  defp to_map(payload) when is_list(payload), do: Enum.into(payload, %{})
end
