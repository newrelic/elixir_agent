defmodule PhxExample.MixProject do
  use Mix.Project

  def project do
    [
      app: :phx_example,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.7",
      compilers: [:phoenix] ++ Mix.compilers(),
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      mod: {PhxExample.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  defp deps do
    [
      {:new_relic_agent, path: "../../../"},
      {:test_support, in_umbrella: true},
      {:phoenix, "~> 1.5"},
      {:phoenix_html, "~> 2.11"},
      {:jason, "~> 1.0"},
      {:plug_cowboy, "~> 2.0"}
    ]
  end
end
