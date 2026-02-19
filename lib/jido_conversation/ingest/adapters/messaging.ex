defmodule JidoConversation.Ingest.Adapters.Messaging do
  @moduledoc """
  Messaging ingress adapter.
  """

  alias JidoConversation.Ingest

  @spec ingest_received(String.t(), String.t(), String.t(), map() | keyword(), keyword()) ::
          {:ok, JidoConversation.Ingest.Pipeline.ingest_result()}
          | {:error, JidoConversation.Ingest.Pipeline.ingest_error()}
  def ingest_received(conversation_id, message_id, ingress, payload \\ %{}, opts \\ [])
      when is_binary(conversation_id) and is_binary(message_id) and is_binary(ingress) do
    payload = to_map(payload)

    signal = %{
      type: "conv.in.message.received",
      source: "/messaging/#{ingress}",
      subject: conversation_id,
      data:
        Map.merge(payload, %{
          message_id: message_id,
          ingress: ingress
        }),
      extensions: %{contract_major: 1}
    }

    Ingest.ingest(signal, opts)
  end

  defp to_map(payload) when is_map(payload), do: payload
  defp to_map(payload) when is_list(payload), do: Enum.into(payload, %{})
end
