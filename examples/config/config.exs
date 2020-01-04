use Mix.Config

if File.exists?("config/secret.exs"), do: import_config("secret.exs")

import_config "../apps/*/config/config.exs"
