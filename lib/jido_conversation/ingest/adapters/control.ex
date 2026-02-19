defmodule JidoConversation.Ingest.Adapters.Control do
  @moduledoc """
  Control-plane ingress adapter.
  """

  alias JidoConversation.Ingest

  @spec ingest_abort(String.t(), String.t(), map() | keyword(), keyword()) ::
          {:ok, JidoConversation.Ingest.Pipeline.ingest_result()}
          | {:error, JidoConversation.Ingest.Pipeline.ingest_error()}
  def ingest_abort(conversation_id, control_id, payload \\ %{}, opts \\ [])
      when is_binary(conversation_id) and is_binary(control_id) do
    payload = to_map(payload)

    signal = %{
      type: "conv.in.control.abort_requested",
      source: "/control/user",
      subject: conversation_id,
      data:
        Map.merge(payload, %{
          message_id: control_id,
          ingress: "control"
        }),
      extensions: %{contract_major: 1}
    }

    Ingest.ingest(signal, opts)
  end

  defp to_map(payload) when is_map(payload), do: payload
  defp to_map(payload) when is_list(payload), do: Enum.into(payload, %{})
end
