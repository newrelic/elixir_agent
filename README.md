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
