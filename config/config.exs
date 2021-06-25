use Mix.Config

config :new_relic_agent, NewRelic.Util.HTTP, proxy: nil

if Mix.env() == :test, do: import_config("test.exs")
if File.exists?("config/secret.exs"), do: import_config("secret.exs")
