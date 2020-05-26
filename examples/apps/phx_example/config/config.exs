use Mix.Config

config :phx_example, PhxExampleWeb.Endpoint,
  url: [host: "localhost"],
  render_errors: [view: PhxExampleWeb.ErrorView, accepts: ~w(html json), layout: false],
  http: [port: 4003],
  server: true

config :phoenix, :json_library, Jason
