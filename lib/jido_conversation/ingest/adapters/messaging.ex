defmodule JidoConversation.Ingest.Adapters.Messaging do
  @moduledoc """
  Messaging ingress adapters.

  `ingest_received/5` handles already-normalized ingress fields.
  `ingest_channel_message/2` accepts a generic channel payload (e.g. from
  jido_messaging style integrations) and normalizes it into the same event.
  """

  alias JidoConversation.Ingest

  @type adapter_error ::
          {:invalid_message_payload, atom(), term()}
          | {:invalid_message_payload, :message, term()}

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

  @spec ingest_channel_message(map(), keyword()) ::
          {:ok, JidoConversation.Ingest.Pipeline.ingest_result()}
          | {:error, JidoConversation.Ingest.Pipeline.ingest_error() | adapter_error()}
  def ingest_channel_message(message, opts \\ [])

  def ingest_channel_message(message, opts) when is_map(message) do
    with {:ok, conversation_id} <-
           required_binary(message, [:conversation_id, :subject, :thread_id]),
         {:ok, message_id} <- required_binary(message, [:message_id, :id]),
         ingress <- ingress_for(message),
         payload <- channel_payload(message) do
      ingest_received(conversation_id, message_id, ingress, payload, opts)
    end
  end

  def ingest_channel_message(message, _opts) do
    {:error, {:invalid_message_payload, :message, message}}
  end

  defp to_map(payload) when is_map(payload), do: payload
  defp to_map(payload) when is_list(payload), do: Enum.into(payload, %{})

  defp channel_payload(message) do
    base =
      message
      |> drop_keys([:conversation_id, :subject, :thread_id, :message_id, :id, :ingress])
      |> drop_keys(["conversation_id", "subject", "thread_id", "message_id", "id", "ingress"])

    base
    |> maybe_put(:content, first_present(message, [:content, :text, :body]))
    |> maybe_put(:role, normalize_role(get_field(message, :role)))
    |> maybe_put(:channel, first_present(message, [:channel, :ingress]))
    |> maybe_put(:sender_id, first_present(message, [:sender_id, :author_id, :user_id]))
    |> maybe_put(:metadata, normalize_map(get_field(message, :metadata)))
  end

  defp ingress_for(message) do
    first_present(message, [:ingress, :channel, :transport]) || "jido_messaging"
  end

  defp required_binary(message, keys) when is_list(keys) do
    case first_present(message, keys) do
      value when is_binary(value) and value != "" ->
        {:ok, value}

      value ->
        {:error, {:invalid_message_payload, hd(keys), value}}
    end
  end

  defp first_present(message, keys) do
    Enum.find_value(keys, fn key ->
      message
      |> get_field(key)
      |> present_value()
    end)
  end

  defp normalize_role(nil), do: nil
  defp normalize_role(role) when is_atom(role), do: Atom.to_string(role)
  defp normalize_role(role) when is_binary(role), do: role
  defp normalize_role(role), do: inspect(role)

  defp normalize_map(value) when is_map(value), do: value
  defp normalize_map(_value), do: %{}

  defp drop_keys(map, keys) when is_map(map) and is_list(keys) do
    Enum.reduce(keys, map, &Map.delete(&2, &1))
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp get_field(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, to_string(key))
  end

  defp present_value(value) when is_binary(value) do
    if String.trim(value) == "", do: nil, else: value
  end

  defp present_value(value), do: value
end
