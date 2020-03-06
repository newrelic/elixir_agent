defmodule RedixExample.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  def start(_type, _args) do
    http_port = Application.get_env(:redix_example, :http_port)

    children = [
      {Redix, host: "localhost", name: :redix},
      Plug.Cowboy.child_spec(scheme: :http, plug: RedixExample.Router, options: [port: http_port])
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: RedixExample.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
