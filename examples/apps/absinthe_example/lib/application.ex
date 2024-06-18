defmodule AbsintheExample.Application do
  @moduledoc false
  use Application

  def start(_type, _args) do
    http_port = Application.get_env(:absinthe_example, :http_port)

    children = [
      Plug.Cowboy.child_spec(
        scheme: :http,
        plug: AbsintheExample.Router,
        options: [port: http_port]
      )
    ]

    opts = [strategy: :one_for_one, name: AbsintheExample.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
