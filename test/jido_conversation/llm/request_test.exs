defmodule Jido.Conversation.LLM.RequestTest do
  use ExUnit.Case, async: true

  alias Jido.Conversation.LLM.Request

  test "new/1 validates required fields and message shape" do
    assert {:error, {:field, :request_id, :missing}} =
             Request.new(%{conversation_id: "c1", backend: :jido_ai, messages: [%{role: :user}]})
  end

  test "new/1 preserves explicit stream false and accepts string keys" do
    attrs = %{
      "request_id" => "r1",
      "conversation_id" => "c1",
      "backend" => :jido_ai,
      "messages" => [%{"role" => "user", "content" => "hi"}],
      "stream?" => false
    }

    assert {:ok, request} = Request.new(attrs)
    assert request.stream? == false
    assert request.backend == :jido_ai
  end

  test "new/1 rejects empty message list" do
    assert {:error, {:messages, :empty}} =
             Request.new(%{
               request_id: "r1",
               conversation_id: "c1",
               backend: :jido_ai,
               messages: []
             })
  end

  test "new/1 rejects invalid message entries" do
    assert {:error, {:message, 0, :invalid}} =
             Request.new(%{
               request_id: "r1",
               conversation_id: "c1",
               backend: :jido_ai,
               messages: [%{role: :user}]
             })
  end

  test "new/1 rejects invalid stream value" do
    assert {:error, {:field, :stream?, :invalid}} =
             Request.new(%{
               request_id: "r1",
               conversation_id: "c1",
               backend: :jido_ai,
               messages: [%{role: :user, content: "hello"}],
               stream?: "false"
             })
  end

  test "new/1 rejects invalid metadata shape" do
    assert {:error, {:field, :metadata, :invalid}} =
             Request.new(%{
               request_id: "r1",
               conversation_id: "c1",
               backend: :jido_ai,
               messages: [%{role: :user, content: "hello"}],
               metadata: 123
             })
  end
end
