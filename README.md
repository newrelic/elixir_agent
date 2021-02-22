[![Community Project header](https://github.com/newrelic/open-source-office/raw/master/examples/categories/images/Community_Project.png)](https://github.com/newrelic/open-source-office/blob/master/examples/categories/index.md#category-community-project)

# New Relic's Elixir Agent

[![Build Status](https://github.com/newrelic/elixir_agent/workflows/CI/badge.svg)](https://github.com/newrelic/elixir_agent/actions?query=workflow%3ACI)
[![Hex.pm Version](https://img.shields.io/hexpm/v/new_relic_agent.svg)](https://hex.pm/packages/new_relic_agent)
[![Hex Docs](https://img.shields.io/badge/hex-docs-blue.svg)](https://hexdocs.pm/new_relic_agent/)
[![License](https://img.shields.io/badge/license-Apache%202-blue.svg)](https://opensource.org/licenses/Apache-2.0)

The Open-Source Elixir Agent allows you to monitor your `Elixir` applications with New Relic. It helps you track transactions, distributed traces and other parts of your application's behavior and provides an overview of underlying [BEAM activity](https://github.com/newrelic/elixir_agent/wiki/BEAM-stats-page).

[View the Documentation](https://hexdocs.pm/new_relic_agent)

### Support Statement

New Relic has open-sourced this project to enable monitoring of `Elixir` applications. This project is provided AS-IS WITHOUT WARRANTY OR SUPPORT, although you can report issues and contribute to the project here on GitHub.

### Contributing

We'd love to get your contributions to improve the elixir agent! Keep in mind when you submit your pull request, you'll need to sign the CLA via the click-through using CLA-Assistant. If you'd like to execute our corporate CLA, or if you have any questions, please drop us an email at [open-source@newrelic.com](mailto:open-source@newrelic.com). 

## Installation

Install the [Hex package](https://hex.pm/packages/new_relic_agent)

Requirements:
* Erlang/OTP 21
* Elixir 1.8

```elixir
defp deps do
  [
    {:new_relic_agent, "~> 1.0"}
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

## Telemetry

Some common Elixir packages are auto-instrumented via [`telemetry`](https://github.com/beam-telemetry/telemetry)

* [`Plug`](https://github.com/elixir-plug/plug): See [NewRelic.Telemetry.Plug](https://hexdocs.pm/new_relic_agent/NewRelic.Telemetry.Plug.html) for details.
* [`Phoenix`](https://github.com/phoenixframework/phoenix): See [NewRelic.Telemetry.Phoenix](https://hexdocs.pm/new_relic_agent/NewRelic.Telemetry.Phoenix.html) for details.
* [`Ecto`](https://github.com/elixir-ecto/ecto): See [NewRelic.Telemetry.Ecto](https://hexdocs.pm/new_relic_agent/NewRelic.Telemetry.Ecto.html) for details.
* [`Redix`](https://github.com/whatyouhide/redix): See [NewRelic.Telemetry.Redix](https://hexdocs.pm/new_relic_agent/NewRelic.Telemetry.Redix.html) for details.

## Custom Instrumentation

#### Function Tracing

* `NewRelic.Tracer` enables detailed Function tracing. Annotate a function and it'll show up as a span in Transaction Traces / Distributed Traces, and we'll collect aggregate stats about it. Install it by adding `use NewRelic.Tracer` to any module, and annotating any function with `@trace` module attribute

```elixir
defmodule MyModule do
  use NewRelic.Tracer

  @trace :func
  def func do
    # Will report as `MyModule.func/0`
  end
end
```

#### Distributed Tracing

* Requests to other services can be traced with the combination of an additional outgoing header and an `:external` tracer.

```elixir
defmodule MyExternalService do
  use NewRelic.Tracer

  @trace {:request, category: :external}
  def request(method, url, headers) do
    NewRelic.set_span(:http, url: url, method: method, component: "HttpClient")
    headers = headers ++ NewRelic.distributed_trace_headers(:http)
    HttpClient.request(method, url, headers)
  end
end
```

#### Pre-Instrumented Modules

* `NewRelic.Instrumented.Mix.Task` To enable the Agent and record an Other Transaction during a `Mix.Task`, simply `use NewRelic.Instrumented.Mix.Task`. This will ensure the agent is properly started, records the Transaction, and is shut down.

```elixir
defmodule Mix.Tasks.Example do
  use Mix.Task
  use NewRelic.Instrumented.Mix.Task

  def run(args) do
    # ...
  end
end
```

* `NewRelic.Instrumented.HTTPoison` Automatically wraps HTTP calls in a span, and adds an outbound header to track the request as part of a Distributed Trace.

```elixir
alias NewRelic.Instrumented.HTTPoison
HTTPoison.get("http://www.example.com")
```

#### Other Transactions

You may start an "Other" Transaction for non-HTTP related work. This could used be while consuming from a message queue, for example.

To start an Other Transaction:

```elixir
NewRelic.start_transaction(category, name)
```

And to stop the Transaction within the same process:

```elixir
NewRelic.stop_transaction()
```

#### Adapters

There are a few adapters which leverage this agent to provide library / framework specific instrumentation. Note that these will eventually be replaced with `telemetry` based instrumentation.

* `Absinthe` https://github.com/binaryseed/new_relic_absinthe
