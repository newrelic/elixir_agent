use Mix.Config

if File.exists?("config/secret.exs"), do: import_config("secret.exs")

config :logger, level: :warn

# Pretend the agent is connected
config :new_relic_agent,
  app_name: "ExampleApps",
  license_key: "license_key",
  trusted_account_key: "trusted_account_key"

import_config "../apps/*/config/config.exs"
