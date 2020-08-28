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
  def app_name do
    (System.get_env("NEW_RELIC_APP_NAME") || Application.get_env(:new_relic_agent, :app_name))
    |> parse_app_names
  end

  @doc """
  **Required**

  Configure your New Relic License Key.

  License Key can be configured in two ways, though using Environment Variables is strongly
  recommended to keep secrets out of source code:
  * Environment variables: `NEW_RELIC_LICENSE_KEY=abc123`
  * Application config: `config :new_relic_agent, license_key: "abc123"`
  """
  def license_key,
    do:
      System.get_env("NEW_RELIC_LICENSE_KEY") ||
        Application.get_env(:new_relic_agent, :license_key)

  @doc false
  def host,
    do: System.get_env("NEW_RELIC_HOST") || Application.get_env(:new_relic_agent, :host)

  @doc """
  Configure the Agent logging mechanism.

  This controls how the Agent logs it's own behavior, and doesn't impact your
  applications own logging at all.

  Defaults to the File `"tmp/new_relic.log"`.

  Options:
  - `"stdout"` Write directly to Standard Out
  - `"Logger"` Send Agent logs to Elixir's Logger
  - `"file_name.log"` Write to a chosen file

  Agent logging can be configured in two ways:
  * Environment variable: `NEW_RELIC_LOG=stdout`
  * Application config: `config :new_relic_agent, log: "stdout"`
  """
  def logger,
    do: System.get_env("NEW_RELIC_LOG") || Application.get_env(:new_relic_agent, :log)

  @doc """
  An optional list of key/value pairs that will be automatic custom attributes
  on all event types reported (Transactions, etc).

  Options:
  - `{:system, "ENV_NAME"}` Read a System ENV variable
  - `{module, function, args}` Call a function. Warning: Be very careful, this will get called a lot!
  - `"foo"` A direct value

  This feature is only configurable with `Application` config.

  Example:

  ```
  config :new_relic_agent,
    automatic_attributes: [
      environment: {:system, "APP_ENV"},
      node_name: {Node, :self, []},
      team_name: "Afterlife"
    ]
  ```
  """
  def automatic_attributes do
    Application.get_env(:new_relic_agent, :automatic_attributes, [])
    |> Enum.into(%{}, fn
      {name, {:system, env_var}} -> {name, System.get_env(env_var)}
      {name, {m, f, a}} -> {name, apply(m, f, a)}
      {name, value} -> {name, value}
    end)
  end

  @doc """
  An optional list of labels that will be applied to the application.

  Configured with a single string containing a list of key-value pairs:

  `key1:value1;key2:value2`

  The delimiting characters `;` and `:` are not allowed in the `key` or `value`

  Labels can be configured in two ways:
  * Environment variables: `NEW_RELIC_LABELS=region:west;env:prod`
  * Application config: `config :new_relic_agent, labels: "region:west;env:prod"`
  """
  def labels do
    (System.get_env("NEW_RELIC_LABELS") || Application.get_env(:new_relic_agent, :labels))
    |> parse_labels()
  end

  @doc """
  Some Agent features can be toggled via configuration

  ### Security

  * `:error_collector_enabled` (default `true`)
    * Toggles collection of any Error traces or metrics
  * `:db_query_collection_enabled` (default `true`)
    * Toggles collection of Database query strings
  * `function_argument_collection_enabled` (default `true`)
    * Toggles collection of traced function arguments

  ### Instrumentation

  Opting out of Instrumentation means that `:telemetry` handlers
  will not be attached, reducing the performance impact to zero.

  * `:ecto_instrumentation_enabled` (default `true`)
    * Controls all Ecto instrumentation
  * `:redix_instrumentation_enabled` (default `true`)
    * Controls all Redix instrumentation

  ### Configuration

  Each of these features can be configured in two ways, for example:
  * Environment variables: `NEW_RELIC_ERROR_COLLECTOR_ENABLED=false`
  * Application config: `config :new_relic_agent, error_collector_enabled: false`
  """
  def feature?(:error_collector) do
    feature_check?("NEW_RELIC_ERROR_COLLECTOR_ENABLED", :error_collector_enabled)
  end

  def feature?(:db_query_collection) do
    feature_check?("NEW_RELIC_SQL_COLLECTION_ENABLED", :sql_collection_enabled, false) ||
      feature_check?("NEW_RELIC_DB_QUERY_COLLECTION_ENABLED", :db_query_collection_enabled)
  end

  def feature?(:ecto_instrumentation) do
    feature_check?("NEW_RELIC_ECTO_INSTRUMENTATION_ENABLED", :ecto_instrumentation_enabled)
  end

  def feature?(:redix_instrumentation) do
    feature_check?("NEW_RELIC_REDIX_INSTRUMENTATION_ENABLED", :redix_instrumentation_enabled)
  end

  def feature?(:function_argument_collection) do
    feature_check?(
      "NEW_RELIC_FUNCTION_ARGUMENT_COLLECTION_ENABLED",
      :function_argument_collection_enabled
    )
  end

  @doc """
  Some Agent features can be controlled via configuration

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
  """
  def feature(:logs_in_context) do
    case System.get_env("NEW_RELIC_LOGS_IN_CONTEXT") do
      nil -> Application.get_env(:new_relic_agent, :logs_in_context, :disabled)
      "forwarder" -> :forwarder
      "direct" -> :direct
      _ -> :disabled
    end
  end

  defp feature_check?(env, config, default \\ true) do
    case System.get_env(env) do
      "true" -> true
      "false" -> false
      _ -> Application.get_env(:new_relic_agent, config, default)
    end
  end

  @doc false
  def enabled?, do: (harvest_enabled?() && app_name() && license_key() && true) || false

  @doc false
  def region_prefix,
    do: Application.get_env(:new_relic_agent, :region_prefix)

  @doc false
  def event_harvest_config() do
    %{
      harvest_limits: %{
        analytic_event_data:
          Application.get_env(:new_relic_agent, :analytic_event_per_minute, 1000),
        custom_event_data: Application.get_env(:new_relic_agent, :custom_event_per_minute, 1000),
        error_event_data: Application.get_env(:new_relic_agent, :error_event_per_minute, 100),
        span_event_data: Application.get_env(:new_relic_agent, :span_event_per_minute, 1000)
      }
    }
  end

  defp harvest_enabled?,
    do:
      System.get_env("NEW_RELIC_HARVEST_ENABLED") == "true" ||
        Application.get_env(:new_relic_agent, :harvest_enabled, true)

  defp parse_app_names(nil), do: nil

  defp parse_app_names(name_string) do
    name_string
    |> String.split(";")
    |> Enum.map(&String.trim/1)
  end

  defp parse_labels(nil), do: []

  @label_splitter ~r/;|:/
  defp parse_labels(label_string) do
    label_string
    |> String.split(@label_splitter, trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.chunk_every(2, 2, :discard)
  end

  @external_resource "VERSION"
  @agent_version "VERSION" |> File.read!() |> String.trim()

  @doc false
  def agent_version, do: @agent_version
end
