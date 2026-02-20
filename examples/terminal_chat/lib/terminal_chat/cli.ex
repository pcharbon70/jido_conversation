defmodule TerminalChat.CLI do
  @moduledoc """
  Entrypoint for running the TermUI application.
  """

  @spec run(keyword()) :: :ok | {:error, term()}
  def run(opts \\ []) do
    opts =
      opts
      |> Keyword.put_new(:root, TerminalChat.UI.Root)
      |> Keyword.put_new(:render_interval, 33)

    TermUI.Runtime.run(opts)
  end
end
