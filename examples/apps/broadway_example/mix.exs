defmodule BroadwayExample.MixProject do
  use Mix.Project

  def project do
    [
      app: :broadway_example,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      elixirc_paths: elixirc_paths(Mix.env()),
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.9",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {BroadwayExample.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:new_relic_agent, path: "../../../"},
      {:broadway, "~> 0.6"}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", Path.expand("../../../test/support")]
  defp elixirc_paths(_), do: ["lib"]
end
