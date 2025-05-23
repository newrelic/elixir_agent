defmodule NewRelic.Mixfile do
  use Mix.Project

  @source_url "https://github.com/newrelic/elixir_agent"

  def project do
    [
      app: :new_relic_agent,
      description: "New Relic's Open-Source Elixir Agent",
      version: agent_version(),
      elixir: "~> 1.11",
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      name: "New Relic Elixir Agent",
      source_url: @source_url,
      elixirc_paths: elixirc_paths(Mix.env()),
      package: package(),
      deps: deps(),
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :inets, :ssl, {:os_mon, :optional}],
      mod: {NewRelic.Application, []}
    ]
  end

  defp package do
    [
      files: ["lib", "mix.exs", "README.md", "CHANGELOG.md", "VERSION"],
      maintainers: ["Vince Foley"],
      licenses: ["Apache-2.0"],
      links: %{
        "Changelog" => "#{@source_url}/blob/master/CHANGELOG.md",
        "GitHub" => @source_url
      }
    ]
  end

  defp deps do
    [
      {:ex_doc, ">= 0.0.0", only: :dev},
      {:castore, ">= 0.1.0"},
      {:jason, "~> 1.0", optional: true},
      {:telemetry, "~> 0.4 or ~> 1.0"},
      # Instrumentation:
      {:plug, ">= 1.10.4", optional: true},
      {:plug_cowboy, ">= 2.4.0", optional: true},
      {:bandit, ">= 1.0.0", optional: true},
      {:phoenix, ">= 1.5.5", optional: true},
      {:ecto_sql, ">= 3.4.0", optional: true},
      {:ecto, ">= 3.9.5", optional: true},
      {:redix, ">= 0.11.0", optional: true},
      {:oban, ">= 2.0.0", optional: true},
      {:finch, ">= 0.18.0", optional: true},
      {:absinthe, ">= 1.6.0", optional: true}
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v" <> agent_version(),
      extras: ["README.md", "CHANGELOG.md"]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  @agent_version File.read!("VERSION") |> String.trim()
  def agent_version, do: @agent_version
end
