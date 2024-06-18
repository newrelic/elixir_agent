import Config

config :phx_example, PhxExampleWeb.Endpoint,
  url: [host: "localhost"],
  render_errors: [formats: [html: PhxExampleWeb.ErrorHTML], layout: false],
  http: [port: 4004],
  server: true,
  adapter: Phoenix.Endpoint.Cowboy2Adapter,
  pubsub_server: PhxExample.PubSub,
  live_view: [signing_salt: "dB7qn7EQ"],
  secret_key_base: "A+gtEDayUNx4ZyfHvUKETwRC4RjxK0FDlrLjuRhaBnr3Ll3ynfu5RlSSGe5E7zbW"

config :logger, level: :warning

config :phoenix, :json_library, Jason
