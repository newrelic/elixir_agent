defmodule PhxExampleWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :phx_example

  @session_options [
    store: :cookie,
    key: "_phx_example_key",
    signing_salt: "F6n7gjjvL6I61gUB",
    same_site: "Lax"
  ]

  socket "/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session_options]]

  plug Plug.Static,
    at: "/",
    from: :phx_example,
    gzip: false,
    only: PhxExampleWeb.static_paths()

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug PhxExampleWeb.Router
end
