use Mix.Config

config :logger, level: :debug

# Pretend the agent is configured
config :new_relic_agent,
  app_name: "ExampleApps",
  license_key: "license_key",
  trusted_account_key: "trusted_account_key"

import_config "../apps/*/config/config.exs"

if File.exists?("../../config/secret.exs"), do: import_config("secret.exs")
