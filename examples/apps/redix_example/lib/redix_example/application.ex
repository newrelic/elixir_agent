defmodule RedixExample.Application do
  use Application

  def start(_type, _args) do
    http_port = Application.get_env(:redix_example, :http_port)

    children = [
      {Redix, host: "localhost", name: :redix},
      Plug.Cowboy.child_spec(scheme: :http, plug: RedixExample.Router, options: [port: http_port])
    ]

    opts = [strategy: :one_for_one, name: RedixExample.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
