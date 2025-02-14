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
      elixirc_paths: ["lib", Path.expand(__DIR__ <> "../../../../test/support")],
      elixir: "~> 1.7",
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
      {:phoenix, "~> 1.5"},
      {:phoenix_html, "~> 3.3"},
      {:phoenix_view, "~> 2.0"},
      {:phoenix_live_view, "~> 0.20"},
      {:floki, ">= 0.30.0", only: :test},
      {:jason, "~> 1.0"},
      {:plug_cowboy, "~> 2.0"},
      {:bandit, "~> 1.0"}
    ]
  end
end
