defmodule Jido.Conversation.Ingest.Adapters.Llm do
  @moduledoc """
  LLM lifecycle ingress adapter.
  """

  alias Jido.Conversation.Ingest

  @spec ingest_lifecycle(String.t(), String.t(), String.t(), map() | keyword(), keyword()) ::
          {:ok, Jido.Conversation.Ingest.Pipeline.ingest_result()}
          | {:error, Jido.Conversation.Ingest.Pipeline.ingest_error()}
  def ingest_lifecycle(conversation_id, effect_id, lifecycle, payload \\ %{}, opts \\ [])
      when is_binary(conversation_id) and is_binary(effect_id) and is_binary(lifecycle) do
    payload = to_map(payload)

    signal = %{
      type: "conv.effect.llm.generation.#{lifecycle}",
      source: "/llm/runtime",
      subject: conversation_id,
      data:
        Map.merge(payload, %{
          effect_id: effect_id,
          lifecycle: lifecycle
        }),
      extensions: %{contract_major: 1}
    }

    Ingest.ingest(signal, opts)
  end

  defp to_map(payload) when is_map(payload), do: payload
  defp to_map(payload) when is_list(payload), do: Enum.into(payload, %{})
end
