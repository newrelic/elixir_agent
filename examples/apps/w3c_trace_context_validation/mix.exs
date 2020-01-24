defmodule W3cTraceContextValidation.MixProject do
  use Mix.Project

  def project do
    [
      app: :w3c_trace_context_validation,
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
      mod: {W3cTraceContextValidation.Application, []}
    ]
  end

  defp deps do
    [
      {:new_relic_agent, path: "../../../"},
      {:httpoison, "~> 1.0"}
    ]
  end
end
