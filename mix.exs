defmodule JidoConversation.MixProject do
  use Mix.Project

  def project do
    [
      app: :jido_conversation,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      dialyzer: [
        flags: [:error_handling, :underspecs, :unknown, :unmatched_returns],
        ignore_warnings: ".dialyzer_ignore.exs"
      ],
      aliases: aliases(),
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {JidoConversation.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:jido, "~> 2.0"},
      {:jido_signal, "~> 2.0"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false}
    ]
  end

  defp aliases do
    [
      quality: ["format --check-formatted", "credo --strict", "test"]
    ]
  end
end
