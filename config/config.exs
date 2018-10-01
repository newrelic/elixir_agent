use Mix.Config

config :os_mon, start_cpu_sup: false

if Mix.env() == :test, do: import_config("test.exs")
if File.exists?("config/secret.exs"), do: import_config("secret.exs")
