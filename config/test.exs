use Mix.Config

config :logger, level: :warn

config :new_relic_agent,
  harvest_enabled: false,
  app_name: "ElixirAgentTest",
  automatic_attributes: [test_attribute: "test_value"],
  log: "memory"
