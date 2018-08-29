use Mix.Config

config :logger, level: :warn

config :new_relic,
  harvest_enabled: false,
  app_name: "ElixirAgentTest",
  automatic_attributes: [test_attribute: "test_value"],
  log: "memory"

if File.exists?("config/secret.exs"), do: import_config("secret.exs")
