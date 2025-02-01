defmodule InstrumentedTask.MixProject do
  use Mix.Project

  def project do
    [
      app: :instrumented_task,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixirc_paths: ["lib", Path.expand(__DIR__ <> "../../../../test/support")],
      elixir: "~> 1.9",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:new_relic_agent, path: "../../../"}
    ]
  end
end
