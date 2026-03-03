defmodule Jido.Conversation.LLM.ResultTest do
  use ExUnit.Case, async: true

  alias Jido.Conversation.LLM.Result

  test "new/1 builds completed result" do
    assert {:ok, result} =
             Result.new(%{
               request_id: "r1",
               conversation_id: "c1",
               backend: :jido_ai,
               status: :completed,
               text: "hello"
             })

    assert result.status == :completed
    assert result.text == "hello"
  end

  test "new/1 requires an error for failed status" do
    assert {:error, {:status, :error_required}} =
             Result.new(%{
               request_id: "r1",
               conversation_id: "c1",
               backend: :jido_ai,
               status: :failed
             })
  end

  test "new/1 rejects error on completed status" do
    assert {:error, {:status, :error_forbidden}} =
             Result.new(%{
               request_id: "r1",
               conversation_id: "c1",
               backend: :jido_ai,
               status: :completed,
               error: %{category: :provider, message: "bad"}
             })
  end

  test "new/1 accepts string keys" do
    assert {:ok, result} =
             Result.new(%{
               "request_id" => "r1",
               "conversation_id" => "c1",
               "backend" => :harness,
               "status" => :canceled,
               "error" => %{"category" => :canceled, "message" => "aborted"}
             })

    assert result.status == :canceled
    assert result.error.category == :canceled
  end

  test "new/1 rejects invalid usage shape" do
    assert {:error, {:field, :usage, :invalid}} =
             Result.new(%{
               request_id: "r1",
               conversation_id: "c1",
               backend: :jido_ai,
               status: :completed,
               usage: 1
             })
  end
end
