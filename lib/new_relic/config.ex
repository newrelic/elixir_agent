defmodule NewRelic.Config do
  @moduledoc """
  New Relic Agent Configuration

  All configuration items can be set via ENV variable _or_ via Application config
  """

  @doc "Configure your application name. **Required**"
  def app_name,
    do: System.get_env("NEW_RELIC_APP_NAME") || Application.get_env(:new_relic, :app_name)

  @doc "Configure your New Relic License Key. **Required**"
  def license_key,
    do: System.get_env("NEW_RELIC_LICENSE_KEY") || Application.get_env(:new_relic, :license_key)

  @doc "Configure the host to report to. Most customers have no need to set this."
  def host,
    do: System.get_env("NEW_RELIC_HOST") || Application.get_env(:new_relic, :host)

  @doc """
  Configure the Agent logging mechanism. Defaults to `"tmp/new_relic.log"`

  Options:
  - `"stdout"`
  - `"memory"` (Useful for testing)
  - `"file_name.log"`
  """
  def logger,
    do: System.get_env("NEW_RELIC_LOG") || Application.get_env(:new_relic, :log)

  @doc """
  An optional list of key/value pairs that will be automatic custom attributes
  on all event types reported (Transactions, etc)

  Options:
  - `{:system, "ENV_NAME"}` Read a System ENV variable
  - `{module, function, args}` Call a function. Warning: Be very careful, this will get called a lot!
  - `"foo"` A direct value

  Example:

  ```
  config :new_relic,
    automatic_attributes: [
      environment: {:system, "APP_ENV"},
      node_name: {Node, :self, []},
      team_name: "Afterlife"
    ]
  ```
  """
  def automatic_attributes do
    Application.get_env(:new_relic, :automatic_attributes, [])
    |> Enum.into(%{}, fn
      {name, {:system, env_var}} -> {name, System.get_env(env_var)}
      {name, {m, f, a}} -> {name, apply(m, f, a)}
      {name, value} -> {name, value}
    end)
  end

  @doc false
  def enabled?, do: (harvest_enabled?() && app_name() && license_key() && true) || false

  defp harvest_enabled?,
    do:
      System.get_env("NEW_RELIC_HARVEST_ENABLED") ||
        Application.get_env(:new_relic, :harvest_enabled, true)

  @external_resource "VERSION"
  @agent_version "VERSION" |> File.read!() |> String.trim()

  @doc false
  def agent_version, do: @agent_version
end
