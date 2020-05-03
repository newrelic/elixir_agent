# New Relic's Open Source Elixir Agent

[![Hex.pm Version](https://img.shields.io/hexpm/v/new_relic_agent.svg)](https://hex.pm/packages/new_relic_agent)
[![Build Status](https://travis-ci.org/newrelic/elixir_agent.svg?branch=master)](https://travis-ci.org/newrelic/elixir_agent)

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

## Instrumentation

Out of the box, we will report Error Traces & some general BEAM VM stats. For further visibility, you'll need to add some basic instrumentation.

#### Telemetry

Some Elixir packages are auto-instrumented via [`telemetry`](https://github.com/beam-telemetry/telemetry)

* [`Ecto`](https://github.com/elixir-ecto/ecto): See [NewRelic.Telemetry.Ecto](https://github.com/newrelic/elixir_agent/blob/master/lib/new_relic/telemetry/ecto.ex) for details.

#### Plug

Plug instrumentation is built into the agent.

* `NewRelic.Transaction` enables rich Transaction Monitoring for a `Plug` pipeline. It's a macro that injects a few plugs and an error handler. Install it by adding `use NewRelic.Transaction` to your Plug module.

```elixir
defmodule MyPlug do
  use Plug.Router
  use NewRelic.Transaction
  # ...
end
```

#### Tracing

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

* `NewRelic.Tracer` also enables detailed External request tracing. A little more instrumentation is required to pass the trace context forward with Distributed Tracing.

```elixir
defmodule MyExternalService do
  use NewRelic.Tracer

  @trace {:request, category: :external}
  def request(method, url, headers) do
    NewRelic.set_span(:http, url: url, method: method, component: "HttpClient")
    headers ++ NewRelic.distributed_trace_headers(:http)
    HttpClient.request(method, url, headers)
  end
end
```

#### `Mix.Task`

To enable the agent during a `Mix.Task`, you simply need to start and stop it.

```elixir
defmodule Mix.Tasks.Example do
  use Mix.Task

  def run(args) do
    Application.ensure_all_started(:new_relic_agent)
    # ...
    Application.stop(:new_relic_agent)
  end
end
```

#### Pre-Instrumented Modules

* `NewRelic.Instrumented.HTTPoison` Automatically wraps HTTP calls in a span, and adds an outbound header to track the request as part of a Distributed Trace.

```elixir
alias NewRelic.Instrumented.HTTPoison
HTTPoison.get("http://www.example.com")
```

#### Adapters

There are a few adapters which leverage this agent to provide library / framework specific instrumentation:

* `Phoenix` https://github.com/binaryseed/new_relic_phoenix
* `Absinthe` https://github.com/binaryseed/new_relic_absinthe

#### Other Transactions

Other transaction is a non-web transaction, so this should only be used in such cases
This could be while consuming messages from a broker, for example

To start a other transaction:
```elixir
NewRelic.start_transaction(category, name)
```

And to stop these transactions within the same process:
```elixir
NewRelic.stop_transaction()
```

Such transactions may end up failing and you can mark then as failed transactions using `NewRelic.Transaction.Reporter`
```
NewRelic.Transaction.Reporter.fail(%{
        kind: "Kind of failure",
        reason: "reason for error",
        stack: __STACKTRACE__
      })
```

A common approach to deal with such transactions and using rescue to mark failures and always ending with `stop_transaction()`
```elixir
def my_func() do
  NewRelic.start_transaction("Task", "MyTask")

  MyTask.exeute(something)

  rescue
    error ->
      NewRelic.Transaction.Reporter.fail(%{
        kind: "#{__MODULE__}.process/1 failed",
        reason: inspect(error),
        stack: __STACKTRACE__
      })
  after
    NewRelic.stop_transaction()
end
```