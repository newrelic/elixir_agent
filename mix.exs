defmodule NewRelic.Mixfile do
  use Mix.Project

  def project do
    [
      app: :new_relic_agent,
      description: "New Relic's Open-Source Elixir Agent",
      version: agent_version(),
      elixir: "~> 1.7",
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      name: "New Relic Elixir Agent",
      source_url: "https://github.com/newrelic/elixir_agent",
      package: package(),
      deps: deps(),
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :inets, :ssl, :os_mon],
      mod: {NewRelic.Application, []}
    ]
  end

  defp package do
    [
      files: ["lib", "priv", "mix.exs", "README.md", "CHANGELOG.md", "VERSION"],
      maintainers: ["Vince Foley"],
      licenses: ["Apache 2.0"],
      links: %{"GitHub" => "https://github.com/newrelic/elixir_agent"}
    ]
  end

  defp deps do
    [
      {:ex_doc, "~> 0.19", only: :dev, runtime: false},
      {:jason, "~> 1.0"},
      {:plug_cowboy, "~> 2.0"},
      {:ssl_verify_fun, "~> 1.1"}
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "CHANGELOG.md"]
    ]
  end

  @agent_version File.read!("VERSION") |> String.trim()
  def agent_version, do: @agent_version
end
