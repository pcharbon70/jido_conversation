defmodule JidoConversation.LLM.ErrorTest do
  use ExUnit.Case, async: true

  alias JidoConversation.LLM.Error

  test "new/1 applies category default retryability when omitted" do
    assert {:ok, error} = Error.new(%{category: :timeout, message: "timed out"})

    assert error.category == :timeout
    assert error.retryable? == true
  end

  test "new/1 preserves explicit false retryable value" do
    attrs = %{"category" => :provider, "message" => "bad request", "retryable?" => false}
    assert {:ok, error} = Error.new(attrs)
    assert error.retryable? == false
  end

  test "from_reason/3 includes reason in details" do
    error = Error.from_reason(:econnreset, :transport)

    assert error.category == :transport
    assert error.retryable? == true
    assert error.details.reason == :econnreset
  end

  test "new/1 rejects unsupported categories" do
    assert {:error, {:category, :unsupported, _categories}} =
             Error.new(%{category: :bad, message: "nope"})
  end

  test "new/1 rejects invalid details shape" do
    assert {:error, {:field, :details, :invalid}} =
             Error.new(%{category: :provider, message: "bad", details: 1})
  end
end
