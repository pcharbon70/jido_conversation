defmodule JidoConversation.LLM.EventTest do
  use ExUnit.Case, async: true

  alias JidoConversation.LLM.Event

  test "new/1 builds a normalized event and error payload" do
    attrs = %{
      request_id: "r1",
      conversation_id: "c1",
      backend: :jido_ai,
      lifecycle: :failed,
      error: %{category: :provider, message: "rate limited"}
    }

    assert {:ok, event} = Event.new(attrs)
    assert event.lifecycle == :failed
    assert event.error.category == :provider
  end

  test "new/1 accepts string keys and trims optional fields" do
    attrs = %{
      "request_id" => "r1",
      "conversation_id" => "c1",
      "backend" => :harness,
      "lifecycle" => :delta,
      "delta" => "  hello "
    }

    assert {:ok, event} = Event.new(attrs)
    assert event.delta == "hello"
  end

  test "new/1 rejects unsupported lifecycle" do
    assert {:error, {:lifecycle, :unsupported, _lifecycles}} =
             Event.new(%{
               request_id: "r1",
               conversation_id: "c1",
               backend: :jido_ai,
               lifecycle: :chunk
             })
  end

  test "new/1 rejects invalid error payload shape" do
    assert {:error, {:error, :invalid}} =
             Event.new(%{
               request_id: "r1",
               conversation_id: "c1",
               backend: :jido_ai,
               lifecycle: :failed,
               error: :bad_error
             })
  end

  test "new/1 rejects invalid usage shape" do
    assert {:error, {:field, :usage, :invalid}} =
             Event.new(%{
               request_id: "r1",
               conversation_id: "c1",
               backend: :jido_ai,
               lifecycle: :delta,
               usage: 1
             })
  end
end
