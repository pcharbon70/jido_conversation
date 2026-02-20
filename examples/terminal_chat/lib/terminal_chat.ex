defmodule TerminalChat do
  @moduledoc """
  Standalone terminal chat example.

  Provides a simple TermUI chat window with:

  - direct LLM chat requests
  - a `/search <query>` web tool call
  - cancellable in-flight requests via `/cancel`
  """

  @spec run(keyword()) :: :ok | {:error, term()}
  def run(opts \\ []) do
    TerminalChat.CLI.run(opts)
  end
end
