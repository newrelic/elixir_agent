defmodule AbsintheExample.Router do
  use Plug.Builder
  use Plug.ErrorHandler

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json, Absinthe.Plug.Parser],
    pass: ["*/*"],
    json_decoder: Jason

  plug Absinthe.Plug, schema: AbsintheExample.Schema

  def handle_errors(conn, error) do
    send_resp(conn, conn.status, "Something went wrong: #{inspect(error)}")
  end
end
