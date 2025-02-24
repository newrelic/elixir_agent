<a href="https://opensource.newrelic.com/oss-category/#new-relic-experimental"><picture><source media="(prefers-color-scheme: dark)" srcset="https://github.com/newrelic/opensource-website/raw/main/src/images/categories/dark/Experimental.png"><source media="(prefers-color-scheme: light)" srcset="https://github.com/newrelic/opensource-website/raw/main/src/images/categories/Experimental.png"><img alt="New Relic Open Source experimental project banner." src="https://github.com/newrelic/opensource-website/raw/main/src/images/categories/Experimental.png"></picture></a>

# New Relic's Elixir agent

[![Build Status](https://github.com/newrelic/elixir_agent/workflows/CI/badge.svg)](https://github.com/newrelic/elixir_agent/actions?query=workflow%3ACI)
[![Hex.pm Version](https://img.shields.io/hexpm/v/new_relic_agent.svg)](https://hex.pm/packages/new_relic_agent)
[![Hex Docs](https://img.shields.io/badge/hex-docs-blue.svg)](https://hexdocs.pm/new_relic_agent/)
[![License](https://img.shields.io/badge/license-Apache%202-blue.svg)](https://opensource.org/licenses/Apache-2.0)

The experimental open-source Elixir agent allows you to monitor your `Elixir` applications with New Relic. It helps you track transactions, distributed traces, other parts of your application's behavior, and provides an overview of underlying BEAM activity.

[View the Documentation](https://hexdocs.pm/new_relic_agent)

### Support Statement

New Relic hosts and moderates an online forum where customers can interact with New Relic employees as well as other customers to get help and share best practices. Like all official New Relic open source projects, there's a related topic in the community forum. You can find this project's topic/threads in the [forum](https://forum.newrelic.com/s/).

### Contributing

We encourage your contributions to improve [project name]! Keep in mind when you submit your pull request, you'll need to sign the CLA via the click-through using CLA-Assistant. You only have to sign the CLA one time per project. If you have any questions, or to execute our corporate CLA, required if your contribution is on behalf of a company, please drop us an email at [opensource@newrelic.com](mailto:opensource@newrelic.com).

A note about vulnerabilities: As noted in our security policy, New Relic is committed to the privacy and security of our customers and their data. We believe that providing coordinated disclosure by security researchers and engaging with the security community are important means to achieve our security goals.

If you believe you have found a security vulnerability in this project or any of New Relic's products or websites, we welcome and greatly appreciate you reporting it to New Relic through HackerOne.

### License
The open-source Elixir agent is licensed under the Apache 2.0 License.

## Installation

Install the [Hex package](https://hex.pm/packages/new_relic_agent)

Requirements:
* Erlang/OTP 24
* Elixir 1.11

```elixir
defp deps do
  [
    {:new_relic_agent, "~> 1.0"}
  ]
end
```

If using an Elixir version before 1.18.x, please also add `:jason` to your dependency list.

```elixir
{:jason, "~> 1.0"}
```

## Configuration

You need to set two required configuration keys so we can authenticate properly.

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

## Telemetry-based auto-instrumentation

Some common Elixir packages are auto-instrumented via [`telemetry`](https://github.com/beam-telemetry/telemetry)

* [`Plug`](https://github.com/elixir-plug/plug): See [NewRelic.Telemetry.Plug](https://hexdocs.pm/new_relic_agent/NewRelic.Telemetry.Plug.html) for details.
* [`Phoenix`](https://github.com/phoenixframework/phoenix): See [NewRelic.Telemetry.Phoenix](https://hexdocs.pm/new_relic_agent/NewRelic.Telemetry.Phoenix.html) for details.
* [`Phoenix LiveView`](https://github.com/phoenixframework/phoenix_live_view): See [NewRelic.Telemetry.PhoenixLiveView](https://hexdocs.pm/new_relic_agent/NewRelic.Telemetry.PhoenixLiveView.html) for details.
* [`Ecto`](https://github.com/elixir-ecto/ecto): See [NewRelic.Telemetry.Ecto](https://hexdocs.pm/new_relic_agent/NewRelic.Telemetry.Ecto.html) for details.
* [`Redix`](https://github.com/whatyouhide/redix): See [NewRelic.Telemetry.Redix](https://hexdocs.pm/new_relic_agent/NewRelic.Telemetry.Redix.html) for details.
* [`Finch`](https://github.com/sneako/finch): See [NewRelic.Telemetry.Finch](https://hexdocs.pm/new_relic_agent/NewRelic.Telemetry.Finch.html) for details.
* [`Oban`](https://github.com/oban-bg/oban): See [NewRelic.Telemetry.Oban](https://hexdocs.pm/new_relic_agent/NewRelic.Telemetry.Oban.html) for details.
* [`Absinthe`](https://github.com/absinthe-graphql/absinthe): See [NewRelic.Telemetry.Absinthe](https://hexdocs.pm/new_relic_agent/NewRelic.Telemetry.Absinthe.html) for details.

## Opt-In agent features

There are a few advanced agent features that can be enabled via configuration. Please see the documentation for more information.

* [Logs In Context](https://hexdocs.pm/new_relic_agent/NewRelic.Config.html#feature/1-logs-in-context) - See your logs in the context of the Transaction / Distributed Trace where they originated.
* [Infinite Tracing](https://hexdocs.pm/new_relic_agent/NewRelic.Config.html#feature/1-infinite-tracing) - Use a New Relic Trace Observer to get tail based sampling of Distributed Traces.
* [Security Controls](https://hexdocs.pm/new_relic_agent/NewRelic.Config.html#feature?/1-security)

## Manual instrumentation

#### Custom Transactions

Transactions are the main unit of work reported to New Relic. `Plug` and `Phoenix` instrumentation automatically report a Web Transaction for each request. `Oban` instrumentation reports an "Other" Transaction for each job. 

You may start an Custom "Other" Transaction for work outside auto-instrumented systems. This could used be while consuming from a message queue, for example.

```elixir
defmodule Worker do
  use NewRelic.Tracer

  def process_messages do
    NewRelic.other_transaction("Worker", "ProcessMessages") do
      # ...
    end
  end
end
```

#### Transaction propagation

Transactions will propagate to any process spawned and linked (ex: `Task.async`), but will _not_ follow a process that isn't linked (ex: `Task.Supervisor.async_nolink`).

If you are using a `Task.Supervisor.async_nolink` to spawn work, you can use the pre-instrumented `NewRelic.Instrumented.Task` wrapper module to make this easier. Just `alias` it in your module and all your Tasks will be instrumented. You may also use the functions directly.

```elixir
alias NewRelic.Instrumented.Task

Task.Supervisor.async_nolink(MyTaskSupervisor, fn ->
  # This process will be automatically connected to the current Transaction...
end)
```

For more fine grained control of Transaction propagation, check out the following functions:

* `NewRelic.exclude_from_transaction/0`
* `NewRelic.ignore_transaction/0`
* `NewRelic.get_transaction/0`
* `NewRelic.connect_to_transaction/1`
* `NewRelic.disconnect_from_transaction/0`

#### Function tracing

`NewRelic.Tracer` enables detailed function tracing. Annotate a function and it'll show up as a span in Transaction Traces / Distributed Traces, and we'll collect aggregate stats about it. Install it by adding `use NewRelic.Tracer` to any module, and annotating any function with an `@trace` module attribute.

```elixir
defmodule MyModule do
  use NewRelic.Tracer

  @trace :work
  def work do
    # Will report as `MyModule.work/0`

    NewRelic.add_span_attributes(some: "attribute")
  end
end
```

If you want to trace a sub-set of a function, you can use the `NewRelic.span` macro.

```elixir
defmodule MyModule do
  use NewRelic.Tracer

  def work do
    # Do some stuff..

    NewRelic.span "do.some_work", user_id: "abc123" do
      # Span will report as `do.some_work` and have a `user_id` attribute
      # Will return the result of the block
    end
  end
end
```

#### Distributed Tracing

Incoming Distributed Traces are automatically connected if incoming HTTP requests have trace headers. Requests to other services can be connected with an additional outgoing header.

```elixir
defmodule MyExternalService do
  def request(method, url, headers) do
    headers = headers ++ NewRelic.distributed_trace_headers(:http)
    HttpClient.request(method, url, headers)
  end
end
```

#### Mix Tasks

`NewRelic.Instrumented.Mix.Task` To enable the agent and record an Other Transaction during a `Mix.Task`, simply `use NewRelic.Instrumented.Mix.Task`. This will ensure the agent is properly started, records a Transaction, and is shut down.

```elixir
defmodule Mix.Tasks.Example do
  use Mix.Task
  use NewRelic.Instrumented.Mix.Task

  def run(args) do
    # ...
  end
end
```

## Advanced configuration

#### HTTP client settings

`:httpc` client settings can be overridden if needed. For example, the HTTP connect timeout can be increased which can help alleviate errors related to timeouts connecting to New Relic:

```elixir
config :new_relic_agent,
  app_name: "My App",
  license_key: "license_key",
  httpc_request_options: [connect_timeout: 5000]
```

#### Ignore paths

You can configure some paths to be automatically ignored:

```elixir
config :new_relic_agent,
  ignore_paths: [
    "/health",
    ~r/longpoll/
  ]
```

#### Disabling

If you want to disable the agent, you can do it in two different ways:

* Application config: `config :new_relic_agent, license_key: nil`
* Environment variables: `NEW_RELIC_HARVEST_ENABLED=false`
