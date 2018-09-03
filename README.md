## New Relic's Open Source Elixir Agent

[![Version](https://img.shields.io/github/tag/newrelic/elixir_agent.svg)](https://github.com/newrelic/elixir_agent/releases)
[![Build Status](https://travis-ci.org/newrelic/elixir_agent.svg?branch=master)](https://travis-ci.org/newrelic/elixir_agent)
[![License](https://img.shields.io/badge/license-Apache%202-blue.svg)](https://github.com/newrelic/elixir_agent/blob/master/LICENSE)

The Open-Source Elixir Agent allows you to monitor your `Elixir` applications with New Relic. It helps you track transactions, distributed traces and other parts of your application's behavior and provides an overview of underlying BEAM activity.

## Support Statement:

New Relic has open-sourced this project to enable monitoring of Elixir. This project is provided AS-IS WITHOUT WARRANTY OR SUPPORT, although you can report issues and contribute to the project here on GitHub.

## Installation

Requirements:
* Elixir `1.7`

```elixir
defp deps do
  [
    {:new_relic_agent, "~> 1.0"},
  ]
end
```

## Configuration

You need to set a few required configuration keys so we can authenticate properly.

#### Via Application config

```elixir
config :new_relic,
  app_name: "My App",
  license_key: "license_key"
```

#### Via Environment variables

You can also configure these attributes via `ENV` vars, which helps keep secrets out of source code.

* `NEW_RELIC_APP_NAME`
* `NEW_RELIC_LICENSE_KEY`


## Logging

The agent will log important events. By default they will go to `tmp/new_relic.log`. You can also configure it to go to `STDOUT` or any other writable file location:

```elixir
config :new_relic,
  log: "stdout"
```

## Feature Support

This agent is an open-source project, not a New Relic product. It has been running in production for more than two years, but we have only implemented a subset of the full New Relic product suite.

Supported features include:

* Transaction events & traces
* Error traces
* Distributed Tracing
* Metrics (very limited support)

The Agent is centered around `Plug` instrumentation. While this should work fine with `Phoenix`, it won't report anything `Phoenix`-specific. We'd love to engage with the community to enable further monitoring solutions to be built on top of what we have provided here.
