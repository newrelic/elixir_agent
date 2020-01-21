# Example applications

A set example apps demonstrating instrumentation.

### Adding example apps

Create the app

```
cd apps
mix new example
```

Point to the agent

```elixir
  def project do
    [
      elixirc_paths: elixirc_paths(Mix.env()),
    ]
  end

  defp deps do
    [
      {:new_relic_agent, path: "../../../"},
    ]
  end

  defp elixirc_paths(:test), do: ["lib", Path.expand("../../../test/support")]
  defp elixirc_paths(_), do: ["lib"]
```
