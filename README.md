# New Relic's Open Source Elixir Agent

[![Version](https://img.shields.io/github/tag/newrelic/elixir_agent.svg)](https://github.com/newrelic/elixir_agent/releases)
[![Build Status](https://travis-ci.org/newrelic/elixir_agent.svg?branch=master)](https://travis-ci.org/newrelic/elixir_agent)
[![License](https://img.shields.io/badge/license-Apache%202-blue.svg)](https://github.com/newrelic/elixir_agent/blob/master/LICENSE)

The Open-Source Elixir Agent allows you to monitor your `Elixir` applications with New Relic. It helps you track transactions, distributed traces and other parts of your application's behavior and provides an overview of underlying BEAM activity.

[View the Documentation](https://hexdocs.pm/new_relic_agent)

## Support Statement

New Relic has open-sourced this project to enable monitoring of `Elixir` applications. This project is provided AS-IS WITHOUT WARRANTY OR SUPPORT, although you can report issues and contribute to the project here on GitHub.

## Installation

Install the [Hex package](https://hex.pm/packages/new_relic_agent)

```elixir
defp deps do
  [
    {:new_relic_agent, "~> 1.0"},
    {:cowboy, "~> 2.0"},
    {:plug, "~> 1.6"}
  ]
end
```

## Configuration

You need to set a few required configuration keys so we can authenticate properly.

#### Via Application config

```elixir
config :new_relic_agent,
  app_name: "My App",
  license_key: "license_key"
```

#### Via Environment variables

You can also configure these attributes via `ENV` vars, which helps keep secrets out of source code.

* `NEW_RELIC_APP_NAME`
* `NEW_RELIC_LICENSE_KEY`

## Instrumentation

Out of the box, we will report Error Traces & some general BEAM VM stats. For further visibility, you'll need to add some basic instrumentation.

* `NewRelic.Transaction` enables rich Transaction Monitoring for a `Plug` pipeline. It's a macro that injects a few plugs and an error handler.

```elixir
defmodule MyApp do
  use Plug.Router
  use NewRelic.Transaction
  # ...
end
```

* `NewRelic.Tracer` enables detailed Function Tracing. Annotate a function and it'll show up as a span in Transaction Traces / Distributed Traces, and we'll collect aggregate stats about it.

```elixir
defmodule MyModule do
  use NewRelic.Tracer

  @trace :func
  def func do
    # Will report as `MyModule.func/0`
  end
end
```

#### Pre-Instrumented Modules

* `NewRelic.Instrumented.HTTPoison` Automatically wraps HTTP calls in a span, and adds an outbound header to track the request as part of a Distributed Trace.

```elixir
alias NewRelic.Instrumented.HTTPoison
HTTPoison.get("http://www.example.com")
```
