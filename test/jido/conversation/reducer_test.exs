defmodule Jido.Conversation.ReducerTest do
  use ExUnit.Case, async: true

  alias Jido.Conversation.Reducer
  alias Jido.Thread

  test "derive/2 builds deterministic state from thread entries" do
    thread =
      Thread.new(id: "thread-1")
      |> Thread.append(%{kind: :message, payload: %{role: "user", content: "hello"}})
      |> Thread.append(%{kind: :note, payload: %{event: "llm_configured", provider: "anthropic"}})
      |> Thread.append(%{kind: :message, payload: %{role: "assistant", content: "hi"}})

    derived = Reducer.derive(Thread.to_list(thread))

    assert derived.turn == 1
    assert derived.status == :responding
    assert derived.last_user_message == "hello"
    assert length(derived.messages) == 2
    assert derived.llm.provider == "anthropic"
  end
end
