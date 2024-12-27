<a href="https://opensource.newrelic.com/oss-category/#new-relic-experimental"><picture><source media="(prefers-color-scheme: dark)" srcset="https://github.com/newrelic/opensource-website/raw/main/src/images/categories/dark/Experimental.png"><source media="(prefers-color-scheme: light)" srcset="https://github.com/newrelic/opensource-website/raw/main/src/images/categories/Experimental.png"><img alt="New Relic Open Source experimental project banner." src="https://github.com/newrelic/opensource-website/raw/main/src/images/categories/Experimental.png"></picture></a>

# New Relic's Elixir agent

[![Build Status](https://github.com/newrelic/elixir_agent/workflows/CI/badge.svg)](https://github.com/newrelic/elixir_agent/actions?query=workflow%3ACI)
[![Hex.pm Version](https://img.shields.io/hexpm/v/new_relic_agent.svg)](https://hex.pm/packages/new_relic_agent)
[![Hex Docs](https://img.shields.io/badge/hex-docs-blue.svg)](https://hexdocs.pm/new_relic_agent/)
[![License](https://img.shields.io/badge/license-Apache%202-blue.svg)](https://opensource.org/licenses/Apache-2.0)

The experimental open-source Elixir agent allows you to monitor your `Elixir` applications with New Relic. It helps you track transactions, distributed traces, other parts of your application's behavior, and provides an overview of underlying [BEAM activity](https://github.com/newrelic/elixir_agent/wiki/BEAM-stats-page).

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
* Erlang/OTP 22
* Elixir 1.9

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

#### HTTP Client Settings

httpc client settings can be overridden if needed. For example, the HTTP connect timeout can be increased which can help alleviate errors related to timeouts connecting to New Relic:

```elixir
config :new_relic_agent,
  app_name: "My App",
  license_key: "license_key",
  httpc_request_options: [connect_timeout: 5000]
```

#### For Elixir 1.15 and higher

Due to changes in the Elixir 1.15 Logger, additional logger configuration is needed for NewRelic to capture all errors. Update your logger configuration by setting `handle_sasl_reports` to `true` and adding `NewRelic.ErrorLogger` to your logger backends.

```elixir
config :logger,
  handle_sasl_reports: true,
  backends: [:console, NewRelic.ErrorLogger]
```

## Telemetry-based Instrumentation

Some common Elixir packages are auto-instrumented via [`telemetry`](https://github.com/beam-telemetry/telemetry)

* [`Plug`](https://github.com/elixir-plug/plug): See [NewRelic.Telemetry.Plug](https://hexdocs.pm/new_relic_agent/NewRelic.Telemetry.Plug.html) for details.
* [`Phoenix`](https://github.com/phoenixframework/phoenix): See [NewRelic.Telemetry.Phoenix](https://hexdocs.pm/new_relic_agent/NewRelic.Telemetry.Phoenix.html) for details.
* [`Ecto`](https://github.com/elixir-ecto/ecto): See [NewRelic.Telemetry.Ecto](https://hexdocs.pm/new_relic_agent/NewRelic.Telemetry.Ecto.html) for details.
* [`Redix`](https://github.com/whatyouhide/redix): See [NewRelic.Telemetry.Redix](https://hexdocs.pm/new_relic_agent/NewRelic.Telemetry.Redix.html) for details.
* [`Finch`](https://github.com/sneako/finch): See [NewRelic.Telemetry.Finch](https://hexdocs.pm/new_relic_agent/NewRelic.Telemetry.Finch.html) for details.

## Agent features

There are a few agent features that can be enabled via configuration. Please see the documentation for more information.

* [Logs In Context](https://hexdocs.pm/new_relic_agent/NewRelic.Config.html#feature/1-logs-in-context)
* [Infinite Tracing](https://hexdocs.pm/new_relic_agent/NewRelic.Config.html#feature/1-infinite-tracing)
* [Security Controls](https://hexdocs.pm/new_relic_agent/NewRelic.Config.html#feature?/1-security)

## Manual Instrumentation

#### Transactions

The `Plug` and `Phoenix` instrumentation automatically report a Transaction for each request.

These Transactions will follow across any process spawned and linked (ex: `Task.async`), but will _not_ follow a process that isn't linked (ex: `Task.Supervisor.async_nolink`).

To manually connect a Transaction to an unlinked process, you can use `NewRelic.get_transaction` and `NewRelic.connect_to_transaction`. See the docs for those functions for further details.

```elixir
tx = NewRelic.get_transaction()

spawn(fn ->
  NewRelic.connect_to_transaction(tx)
  # ...
end)
```

If you are using a `Task` to spawn work, you can use the pre-instrumented `NewRelic.Instrumented.Task` convenience module to make this easier. Just `alias` it in your module and all your Tasks will be instrumented. You may also use the functions directly.

```elixir
alias NewRelic.Instrumented.Task

Task.Supervisor.async_nolink(MyTaskSupervisor, fn ->
  # This process will be automatically connected to the current Transaction...
end)
```

#### Function Tracing

`NewRelic.Tracer` enables detailed Function tracing. Annotate a function and it'll show up as a span in Transaction Traces / Distributed Traces, and we'll collect aggregate stats about it. Install it by adding `use NewRelic.Tracer` to any module, and annotating any function with an `@trace` module attribute

```elixir
defmodule MyModule do
  use NewRelic.Tracer

  @trace :work
  def work do
    # Will report as `MyModule.work/0`
  end
end
```

#### Distributed Tracing

Requests to other services can be connected with an additional outgoing header.

```elixir
defmodule MyExternalService do
  def request(method, url, headers) do
    headers = headers ++ NewRelic.distributed_trace_headers(:http)
    HttpClient.request(method, url, headers)
  end
end
```

#### Pre-Instrumented Modules

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

`NewRelic.Instrumented.HTTPoison` Automatically wraps HTTP calls in a span, and adds an outbound header to track the request as part of a Distributed Trace.

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

#### Disabling

If you want to disable the agent, you can do it in two different ways:

* Application config: `config :new_relic_agent, license_key: nil`
* Environment variables: `NEW_RELIC_HARVEST_ENABLED=false`
