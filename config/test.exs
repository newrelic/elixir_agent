import Config

config :logger, level: :warning

config :new_relic_agent,
  app_name: "ElixirAgentTest",
  automatic_attributes: [test_attribute: "test_value"],
  log: "memory"
