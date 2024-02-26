import Config

config :logger, level: :debug

# Pretend the agent is configured
config :new_relic_agent,
  app_name: "ExampleApps",
  license_key: "license_key",
  trusted_account_key: "trusted_account_key"

for config <- "../apps/*/config/config.exs" |> Path.expand(__DIR__) |> Path.wildcard() do
  import_config config
end

if File.exists?("../../config/secret.exs"), do: import_config("secret.exs")
