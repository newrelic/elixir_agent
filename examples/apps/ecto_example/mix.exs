defmodule EctoExample.MixProject do
  use Mix.Project

  def project do
    [
      app: :ecto_example,
      version: "0.1.0",
      build_path: "../../_build",
      deps_path: "../../deps",
      config_path: "../../config/config.exs",
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
      mod: {EctoExample.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:new_relic_agent, path: "../../../"},
      {:ecto_sql, "~> 3.0"},
      {:postgrex, ">= 0.0.0"},
      {:myxql, ">= 0.0.0"}
    ]
  end
end
