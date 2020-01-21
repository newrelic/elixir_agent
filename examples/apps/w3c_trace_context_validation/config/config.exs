use Mix.Config

config :w3c_trace_context_validation,
  http_port: 4002

config :new_relic_agent,
  app_name: "W3cTraceContextValidation",
  license_key: "asdf",
  trusted_account_key: "190",
  harvest_enabled: true
