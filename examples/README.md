# Example applications

A set example apps demonstrating and validating built-in instrumentation.

### Running tests

In CI, these test are always run. When developing locally, you can run the tests easily by first starting the dependent docker services:

```
docker-compose up
mix test
```

### Adding example apps

Create the app

```
cd apps
mix new --sup example
```

Point to the agent

```elixir
defp deps do
  [
    {:new_relic_agent, path: "../../../"},
    {:test_support, in_umbrella: true},
    # ...
  ]
end
```
