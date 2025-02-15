import Config

config :logger, level: :debug

config :new_relic_agent,
  app_name: "ExampleApps",
  trusted_account_key: "trusted_account_key",
  license_key: "license_key",
  bypass_collector: true

for config <- "../apps/*/config/config.exs" |> Path.expand(__DIR__) |> Path.wildcard() do
  import_config config
end

if Mix.env() != :test do
  if File.exists?(Path.expand("./secret.exs", __DIR__)),
    do: import_config("secret.exs")
end
