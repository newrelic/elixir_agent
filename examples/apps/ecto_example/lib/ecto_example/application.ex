defmodule EctoExample.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  def start(_type, _args) do
    http_port = Application.get_env(:ecto_example, :http_port)

    children = [
      EctoExample.Database,
      Plug.Cowboy.child_spec(scheme: :http, plug: EctoExample.Router, options: [port: http_port]),
      {NewRelic.EctoTelemetry, otp_app: :ecto_example}
    ]

    opts = [strategy: :one_for_one, name: EctoExample.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
