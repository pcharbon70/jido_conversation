defmodule Mix.Tasks.TerminalChat do
  @moduledoc """
  Runs the standalone terminal chat example under `examples/terminal_chat`.

      mix terminal_chat

  Any additional arguments are forwarded to `mix run run.exs` in the example
  project.
  """

  def run(args) when is_list(args) do
    example_dir = Path.expand("examples/terminal_chat", File.cwd!())
    run_script = Path.join(example_dir, "run.exs")

    unless File.exists?(run_script) do
      raise "missing example runner: #{run_script}"
    end

    mix_executable =
      System.find_executable("mix") ||
        raise "could not find `mix` executable in PATH"

    command_args = ["run", "run.exs" | args]
    mix_env = System.get_env("MIX_ENV") || "dev"

    {_output, status} =
      System.cmd(mix_executable, command_args,
        cd: example_dir,
        env: [{"MIX_ENV", mix_env}],
        into: IO.binstream(:stdio, :line),
        stderr_to_stdout: true
      )

    if status != 0 do
      raise "terminal_chat exited with status #{status}"
    end
  end
end
