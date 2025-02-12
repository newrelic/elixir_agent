defmodule NewRelic.Config do
  @moduledoc """
  New Relic Agent Configuration

  All configuration items can be set via Environment variables _or_ via `Application` config
  """

  @doc """
  **Required**

  Configure your application name. May contain up to 3 names seperated by `;`

  Application name can be configured in two ways:
  * Environment variable: `NEW_RELIC_APP_NAME=MyApp`
  * Application config: `config :new_relic_agent, app_name: "MyApp"`
  """
  def app_name,
    do: get(:app_name)

  @doc """
  **Required**

  Configure your New Relic License Key.

  License Key can be configured in two ways, though using Environment Variables is strongly
  recommended to keep secrets out of source code:
  * Environment variables: `NEW_RELIC_LICENSE_KEY=abc123`
  * Application config: `config :new_relic_agent, license_key: "abc123"`
  """
  def license_key,
    do: get(:license_key)

  @doc """
  Configure the Agent host display name.

  This can help connecting data from the Infrastructure Agent to the APM application.

  Host display name can be configured in two ways:
  * Environment variable: `NEW_RELIC_HOST_DISPLAY_NAME=my-host-name`
  * Application config: `config :new_relic_agent, host_display_name: "my-host-name"`
  """
  def host_display_name,
    do: get(:host_display_name)

  @doc """
  Configure the Agent logging mechanism.

  This controls how the Agent logs it's own behavior, and doesn't impact your
  applications own logging at all.

  Defaults to using `Logger`.

  Options:
  - `"Logger"` Send Agent logs to Elixir's `Logger`
  - `"tmp"` Write to `tmp/new_relic.log`
  - `"stdout"` Write directly to Standard Out
  - `"file_name.log"` Write to a chosen file

  Agent logging can be configured in two ways:
  * Environment variable: `NEW_RELIC_LOG=stdout`
  * Application config: `config :new_relic_agent, log: "stdout"`
  """
  def logger,
    do: get(:log)

  @doc """
  An optional list of key/value pairs that will be automatic custom attributes
  on all event types reported (Transactions, etc). Values are determined at Agent
  start.

  Options:
  - `{:system, "ENV_NAME"}` Read a System ENV variable
  - `{module, function, args}` Call a function.
  - `"foo"` A direct value

  This feature is only configurable with `Application` config.

  Example:

  ```elixir
  config :new_relic_agent,
    automatic_attributes: [
      environment: {:system, "APP_ENV"},
      node_name: {Node, :self, []},
      team_name: "Afterlife"
    ]
  ```
  """
  def automatic_attributes,
    do: get(:automatic_attributes)

  @doc """
  An optional list of labels that will be applied to the application.

  Configured with a single string containing a list of key-value pairs:

  `key1:value1;key2:value2`

  The delimiting characters `;` and `:` are not allowed in the `key` or `value`

  Labels can be configured in two ways:
  * Environment variables: `NEW_RELIC_LABELS=region:west;env:prod`
  * Application config: `config :new_relic_agent, labels: "region:west;env:prod"`
  """
  def labels,
    do: get(:labels)

  @doc """
  An optional list of paths that will be used to ignore Web Transactions.

  Individual items can be Strings or Regexes.

  Common use cases include:
  * Ignore health checks: `"/health"`
  * Ignore Phoenix longpoll http requests: `"/live/longpoll"`

  Example:
  ```elixir
  config :new_relic_agent,
    ignore_paths: [
      "/health",
      ~r/longpoll/
    ]
  ```
  """
  def ignore_paths,
    do: get(:ignore_paths)

  @doc """
  Some Agent features can be toggled via configuration. These all default to `true`, but can be configured in two ways:
  * Environment variables: `NEW_RELIC_ERROR_COLLECTOR_ENABLED=false`
  * Application config: `config :new_relic_agent, error_collector_enabled: false`

  ### Built-in features

  * `:distributed_tracing`
    * Toggles reading of incoming distributed tracing headers
  * `:request_queuing_metrics_enabled`
    * Toggles collection of request queuing metrics
  * `:extended_attributes`
    * Toggles reporting extended per-source attributes for datastore, external and function traces

  ### Security

  * `:error_collector_enabled`
    * Toggles collection of any Error traces or metrics
  * `:query_collection_enabled`
    * Toggles collection of any kind of query string
  * `:function_argument_collection_enabled`
    * Toggles collection of traced function arguments

  ### Common library instrumentation

  Opting out of Instrumentation means that `:telemetry` handlers
  will not be attached, reducing the performance impact to zero.

  * `:plug_instrumentation_enabled`
  * `:phoenix_instrumentation_enabled`
  * `:phoenix_live_view_instrumentation_enabled`
  * `:ecto_instrumentation_enabled`
  * `:redix_instrumentation_enabled`
  * `:oban_instrumentation_enabled`
  * `:finch_instrumentation_enabled`
  * `:absinthe_instrumentation_enabled`
  """
  def feature?(toggleable_agent_feature)

  def feature?(:error_collector) do
    get(:features, :error_collector)
  end

  def feature?(:query_collection) do
    get(:features, :query_collection)
  end

  def feature?(:distributed_tracing) do
    get(:features, :distributed_tracing)
  end

  def feature?(:plug_instrumentation) do
    get(:features, :plug_instrumentation)
  end

  def feature?(:phoenix_instrumentation) do
    get(:features, :phoenix_instrumentation)
  end

  def feature?(:phoenix_live_view_instrumentation) do
    get(:features, :phoenix_live_view_instrumentation)
  end

  def feature?(:ecto_instrumentation) do
    get(:features, :ecto_instrumentation)
  end

  def feature?(:redix_instrumentation) do
    get(:features, :redix_instrumentation)
  end

  def feature?(:oban_instrumentation) do
    get(:features, :oban_instrumentation)
  end

  def feature?(:finch_instrumentation) do
    get(:features, :finch_instrumentation)
  end

  def feature?(:absinthe_instrumentation) do
    get(:features, :absinthe_instrumentation)
  end

  def feature?(:function_argument_collection) do
    get(:features, :function_argument_collection)
  end

  def feature?(:stacktrace_argument_collection) do
    get(:features, :stacktrace_argument_collection)
  end

  def feature?(:request_queuing_metrics) do
    get(:features, :request_queuing_metrics)
  end

  def feature?(:extended_attributes) do
    get(:features, :extended_attributes)
  end

  @doc """
  Some Agent features can be controlled via configuration.

  ### Logs In Context

  This feature can be run in multiple "modes":
  * `forwarder` The recommended mode which formats outgoing logs as JSON objects
  ready to be picked up by a [Log Forwarder](https://docs.newrelic.com/docs/logs/enable-log-management-new-relic/enable-log-monitoring-new-relic/enable-log-management-new-relic)
  * `direct` Logs are buffered in the agent and shipped directly to New Relic. Your logs
  will continue being output to their normal destination.
  * `disabled` (default)

  Logs In Context can be configured in two ways:
  * Environment variable `NEW_RELIC_LOGS_IN_CONTEXT=forwarder`
  * Application config `config :new_relic_agent, logs_in_context: :forwarder`

  ### Infinite Tracing

  [Infinite Tracing](https://docs.newrelic.com/docs/understand-dependencies/distributed-tracing/infinite-tracing/introduction-infinite-tracing)
  gives you more control of sampling by collecting 100% of Spans and sending them
  to a Trace Observer for processing.

  You can configure your Trace Observer in two ways:
  * Environment variable `NEW_RELIC_INFINITE_TRACING_TRACE_OBSERVER_HOST=trace-observer.host`
  * Application config `config :new_relic_agent, infinite_tracing_trace_observer_host: "trace-observer.host"`
  """
  def feature(configurable_agent_feature)

  def feature(:logs_in_context) do
    case System.get_env("NEW_RELIC_LOGS_IN_CONTEXT") do
      nil -> Application.get_env(:new_relic_agent, :logs_in_context, :disabled)
      "forwarder" -> :forwarder
      "direct" -> :direct
      other -> other
    end
  end

  def feature(:infinite_tracing) do
    get(:trace_mode)
  end

  @doc false
  def enabled?,
    do: (harvest_enabled?() && app_name() && license_key() && true) || false

  @doc false
  def region_prefix,
    do: get(:region_prefix)

  @doc false
  def event_harvest_config() do
    %{
      harvest_limits: %{
        analytic_event_data: Application.get_env(:new_relic_agent, :analytic_event_per_minute, 1000),
        custom_event_data: Application.get_env(:new_relic_agent, :custom_event_per_minute, 1000),
        error_event_data: Application.get_env(:new_relic_agent, :error_event_per_minute, 100),
        span_event_data: Application.get_env(:new_relic_agent, :span_event_per_minute, 1000)
      }
    }
  end

  defp harvest_enabled?, do: get(:harvest_enabled)

  @doc false
  def get(key), do: :persistent_term.get(:nr_config)[key]
  @doc false
  def get(:features, key), do: :persistent_term.get(:nr_features)[key]

  @doc false
  def put(items), do: :persistent_term.put(:nr_config, items)
  @doc false
  def put(:features, items), do: :persistent_term.put(:nr_features, items)

  @external_resource "VERSION"
  @agent_version "VERSION" |> File.read!() |> String.trim()
  @doc false
  def agent_version, do: @agent_version
end
