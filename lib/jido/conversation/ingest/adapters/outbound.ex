defmodule Jido.Conversation.Ingest.Adapters.Outbound do
  @moduledoc """
  Outbound projection adapter for `conv.out.*` stream events.
  """

  alias Jido.Conversation.Ingest

  @type adapter_error ::
          {:invalid_output_type, term()}
          | {:invalid_conversation_id, term()}
          | {:invalid_output_id, term()}
          | {:invalid_channel, term()}

  @spec ingest_output(
          String.t(),
          String.t(),
          String.t(),
          String.t(),
          map() | keyword(),
          keyword()
        ) ::
          {:ok, Jido.Conversation.Ingest.Pipeline.ingest_result()}
          | {:error, Jido.Conversation.Ingest.Pipeline.ingest_error() | adapter_error()}
  def ingest_output(conversation_id, output_type, output_id, channel, payload \\ %{}, opts \\ [])

  def ingest_output(conversation_id, output_type, output_id, channel, payload, opts)
      when is_binary(conversation_id) and is_binary(output_type) and is_binary(output_id) and
             is_binary(channel) and is_list(opts) do
    with :ok <- validate_non_empty(conversation_id, :invalid_conversation_id),
         :ok <- validate_output_type(output_type),
         :ok <- validate_non_empty(output_id, :invalid_output_id),
         :ok <- validate_non_empty(channel, :invalid_channel) do
      payload = to_map(payload)
      source = Keyword.get(opts, :source, "/runtime/projections")
      cause_id = Keyword.get(opts, :cause_id)

      signal = %{
        type: output_type,
        source: source,
        subject: conversation_id,
        data:
          Map.merge(payload, %{
            output_id: output_id,
            channel: channel
          }),
        extensions: %{contract_major: 1}
      }

      Ingest.ingest(signal, cause_id: cause_id)
    end
  end

  def ingest_output(conversation_id, _output_type, _output_id, _channel, _payload, _opts)
      when not is_binary(conversation_id),
      do: {:error, {:invalid_conversation_id, conversation_id}}

  def ingest_output(_conversation_id, output_type, _output_id, _channel, _payload, _opts)
      when not is_binary(output_type),
      do: {:error, {:invalid_output_type, output_type}}

  def ingest_output(_conversation_id, _output_type, output_id, _channel, _payload, _opts)
      when not is_binary(output_id),
      do: {:error, {:invalid_output_id, output_id}}

  def ingest_output(_conversation_id, _output_type, _output_id, channel, _payload, _opts)
      when not is_binary(channel),
      do: {:error, {:invalid_channel, channel}}

  @spec emit_assistant_delta(
          String.t(),
          String.t(),
          String.t(),
          String.t(),
          map() | keyword(),
          keyword()
        ) ::
          {:ok, Jido.Conversation.Ingest.Pipeline.ingest_result()}
          | {:error, Jido.Conversation.Ingest.Pipeline.ingest_error() | adapter_error()}
  def emit_assistant_delta(
        conversation_id,
        output_id,
        channel,
        delta,
        payload \\ %{},
        opts \\ []
      )
      when is_binary(delta) do
    payload =
      payload
      |> to_map()
      |> Map.put(:delta, delta)

    ingest_output(conversation_id, "conv.out.assistant.delta", output_id, channel, payload, opts)
  end

  @spec emit_assistant_completed(
          String.t(),
          String.t(),
          String.t(),
          String.t(),
          map() | keyword(),
          keyword()
        ) ::
          {:ok, Jido.Conversation.Ingest.Pipeline.ingest_result()}
          | {:error, Jido.Conversation.Ingest.Pipeline.ingest_error() | adapter_error()}
  def emit_assistant_completed(
        conversation_id,
        output_id,
        channel,
        content,
        payload \\ %{},
        opts \\ []
      )
      when is_binary(content) do
    payload =
      payload
      |> to_map()
      |> Map.put(:content, content)

    ingest_output(
      conversation_id,
      "conv.out.assistant.completed",
      output_id,
      channel,
      payload,
      opts
    )
  end

  @spec emit_tool_status(
          String.t(),
          String.t(),
          String.t(),
          String.t(),
          map() | keyword(),
          keyword()
        ) ::
          {:ok, Jido.Conversation.Ingest.Pipeline.ingest_result()}
          | {:error, Jido.Conversation.Ingest.Pipeline.ingest_error() | adapter_error()}
  def emit_tool_status(conversation_id, output_id, channel, status, payload \\ %{}, opts \\ [])
      when is_binary(status) do
    payload =
      payload
      |> to_map()
      |> Map.put(:status, status)

    ingest_output(conversation_id, "conv.out.tool.status", output_id, channel, payload, opts)
  end

  defp to_map(payload) when is_map(payload), do: payload
  defp to_map(payload) when is_list(payload), do: Enum.into(payload, %{})
  defp to_map(_payload), do: %{}

  defp validate_non_empty(value, error_key) when is_binary(value) do
    if String.trim(value) == "" do
      {:error, {error_key, value}}
    else
      :ok
    end
  end

  defp validate_output_type(output_type) when is_binary(output_type) do
    if String.starts_with?(output_type, "conv.out.") do
      :ok
    else
      {:error, {:invalid_output_type, output_type}}
    end
  end
end
