import Config

config :logger,
  handle_sasl_reports: true,
  backends: [NewRelic.ErrorLogger]

if Mix.env() == :test, do: import_config("test.exs")
if File.exists?("config/secret.exs"), do: import_config("secret.exs")
