defmodule AbsintheExample.MixProject do
  use Mix.Project

  def project do
    [
      app: :absinthe_example,
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

  def application do
    [
      extra_applications: [:logger],
      mod: {AbsintheExample.Application, []}
    ]
  end

  defp deps do
    [
      {:new_relic_agent, path: "../../../"},
      {:test_support, in_umbrella: true},
      {:absinthe, "~> 1.6"},
      {:absinthe_plug, "~> 1.5"},
      {:plug_cowboy, "~> 2.0"}
    ]
  end
end
