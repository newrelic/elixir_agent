defmodule NewRelic.Config do
  @moduledoc """
  New Relic Agent Configuration

  All configuration items can be set via `ENV` variable _or_ via `Application` config.

  The following variables can be configured:

  ## App Name ***Required***
    * Application key: `:app_name`
    * Env variable: `NEW_RELIC_APP_NAME`

    The application name.
    May contain up to 3 names seperated by `;`

  ## License key ***Required***
    * Application key: `:license_key`
    * Env variable: `NEW_RELIC_LICENSE_KEY`

    The application license key

  ## Host
    * Application key: `:host`
    * Env variable: `NEW_RELIC_HOST`

    The host to resport to. Most customers have no need to set this

  ## Labels
    * Application key: `:labels`
    * Env variable: `NEW_RELIC_LABELS`

    An optional list of labels that will be applied to the application.

    Configured with a single string containing a list of key-value pairs:

    ```elixir
    "key1:value1;key2:value2"
    ```

    The delimiting characters `;` and `:` are not allowed in the `key` or `value`.

    Example:

    ```elixir
    config :new_relic_agent, labels: "region:west;env:prod"
    ```

  ## Log
    * Application key: :log
    * Env variable: `NEW_RELIC_LOG`

    Configure the Agent logging mechanism.

    Defaults to `"tmp/new_relic.log"`.

    Options:
    - `"stdout"`
    - `"Logger"` Elixir's Logger
    - `"memory"` (Useful for testing)
    - `"file_name.log"`

  ## Automatic Attributes
    * Application key: :automatic_attributes

    An optional list of key/value pairs that will be automatic custom attributes
  on all event types reported (Transactions, etc).

  Options:
  - `{:system, "ENV_NAME"}` Read a System ENV variable
  - `{module, function, args}` Call a function. Warning: Be very careful, this will get called a lot!
  - `"foo"` A direct value

  Example:

  ```
  config :new_relic_agent,
    automatic_attributes: [
      environment: {:system, "APP_ENV"},
      node_name: {Node, :self, []},
      team_name: "Afterlife"
    ]
  ```

  ## Feature toggles
  
  Some Agent features can be controlled via configuration

  ### Security

  * `:error_collector_enabled` (default `true`)
    * Controls collecting any Error traces or metrics
  * `:db_query_collection_enabled` (default `true`)
    * Controls collection of Database query strings
  * `function_argument_collection_enabled` (default `true`)
    * Controls collection of traced function arguments

  ### Instrumentation

  * `:ecto_instrumentation_enabled` (default `true`)
    * Controls all Ecto instrumentation
  * `:redix_instrumentation_enabled` (default `true`)
    * Controls all Redix instrumentation

  """

  @doc """
  Returns your application name.
  """
  def app_name do
    (System.get_env("NEW_RELIC_APP_NAME") || Application.get_env(:new_relic_agent, :app_name))
    |> parse_app_names
  end

  @doc "Returns your New Relic License Key."
  def license_key,
    do:
      System.get_env("NEW_RELIC_LICENSE_KEY") ||
        Application.get_env(:new_relic_agent, :license_key)

  @doc "Returns the host to report to if set to something that isn't the default."
  def host,
    do: System.get_env("NEW_RELIC_HOST") || Application.get_env(:new_relic_agent, :host)

  @doc """
  Returns the Agent logging mechanism behaviour
  """
  def logger,
    do: System.get_env("NEW_RELIC_LOG") || Application.get_env(:new_relic_agent, :log)

  @doc """
  Returns the automatic attributes
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
  Returns the labels
  """
  def labels do
    (System.get_env("NEW_RELIC_LABELS") || Application.get_env(:new_relic_agent, :labels))
    |> parse_labels()
  end

  @doc """
  Returns if a feature is enabled
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

  defp feature_check?(env, config, default \\ true) do
    case System.get_env(env) do
      "true" -> true
      "false" -> false
      _ -> Application.get_env(:new_relic_agent, config, default)
    end
  end

  @doc false
  def enabled?, do: (harvest_enabled?() && app_name() && license_key() && true) || false

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
