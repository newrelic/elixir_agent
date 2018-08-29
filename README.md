## New Relic's Open Source Elixir Agent

### Support Statement:

New Relic has open-sourced this integration to enable monitoring of this technology. This integration is provided AS-IS WITHOUT WARRANTY OR SUPPORT, although you can report issues and contribute to this integration via GitHub.

----

### Installation

Requirements:
* Elixir `1.7`

```elixir
defp deps do
  [
    {:new_relic_agent, "~> 1.0"},
  ]
end
```

----

### Configuration

You need to set a few required configuration keys so we can authenticate properly.

##### Via Application config

```elixir
config :new_relic,
  app_name: "My App",
  license_key: "license_key"
```

##### Via Environment variables

You can also configure these attributes via `ENV` vars, which helps keep secrets out of source code.

* `NEW_RELIC_APP_NAME`
* `NEW_RELIC_LICENSE_KEY`


#### Logging

The agent will log important events. By default they will go to `tmp/new_relic.log`. You can also configure it to go to `STDOUT` or any other writable file location:

```elixir
config :new_relic,
  log: "stdout"
```

----

### Feature Support

This agent is an open-source project, not a New Relic product. It has been running in production for more than two years, but we have only implemented a subset of the full New Relic product suite.

Supported features include:

* Transaction events & traces
* Error traces
* Distributed Tracing
* Metrics (very limited support)

The Agent is centered around `Plug` instrumentation. While this should work fine with `Phoenix`, it won't report anything `Phoenix`-specific. We'd love to engage with the community to enable further monitoring solutions to be built on top of what we have provided here.
