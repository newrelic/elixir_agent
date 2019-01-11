defmodule NewRelic.Config do
  @moduledoc """
  New Relic Agent Configuration

  All configuration items can be set via ENV variable _or_ via Application config
  """

  @doc """
  Configure your application name. **Required**

  May contain up to 3 names seperated by `;`
  """
  def app_name do
    (System.get_env("NEW_RELIC_APP_NAME") || Application.get_env(:new_relic_agent, :app_name))
    |> parse_app_names
  end

  @doc "Configure your New Relic License Key. **Required**"
  def license_key,
    do:
      System.get_env("NEW_RELIC_LICENSE_KEY") ||
        Application.get_env(:new_relic_agent, :license_key)

  @doc "Configure the host to report to. Most customers have no need to set this."
  def host,
    do: System.get_env("NEW_RELIC_HOST") || Application.get_env(:new_relic_agent, :host)

  @doc """
  Configure the Agent logging mechanism.

  Defaults to `"tmp/new_relic.log"`.

  Options:
  - `"stdout"`
  - `"Logger"` Elixir's Logger
  - `"memory"` (Useful for testing)
  - `"file_name.log"`
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

  Example:

  ```
  config :new_relic_agent, labels: "region:west;env:prod"
  ```
  """
  def labels do
    (System.get_env("NEW_RELIC_LABELS") || Application.get_env(:new_relic_agent, :labels))
    |> parse_labels()
  end

  @doc """
  Some Agent features can be controlled via configuration

  * `:error_collector_enabled` (default `true`)
  """
  def feature?(:error_collector) do
    case System.get_env("NEW_RELIC_ERROR_COLLECTOR_ENABLED") do
      "true" -> true
      "false" -> false
      _ -> Application.get_env(:new_relic_agent, :error_collector_enabled, true)
    end
  end

  @doc false
  def enabled?, do: (harvest_enabled?() && app_name() && license_key() && true) || false

  defp harvest_enabled?,
    do:
      System.get_env("NEW_RELIC_HARVEST_ENABLED") ||
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
