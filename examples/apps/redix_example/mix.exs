defmodule RedixExample.MixProject do
  use Mix.Project

  def project do
    [
      app: :redix_example,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
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
      mod: {RedixExample.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:new_relic_agent, path: "../../../"},
      {:test_support, in_umbrella: true},
      {:plug_cowboy, "~> 2.0"},
      {:redix, "~> 1.0"}
    ]
  end
end
