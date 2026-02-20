defmodule TerminalChatTest do
  use ExUnit.Case

  test "session starts and exposes history" do
    assert is_list(TerminalChat.Session.history())
  end
end
