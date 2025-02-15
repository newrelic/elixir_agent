import Config

if Mix.env() == :test do
  import_config("test.exs")
else
  if File.exists?("config/secret.exs"),
    do: import_config("secret.exs")
end
