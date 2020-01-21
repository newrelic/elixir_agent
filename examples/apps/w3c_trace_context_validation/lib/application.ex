defmodule W3cTraceContextValidation.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  def start(_type, _args) do
    http_port = Application.get_env(:w3c_trace_context_validation, :http_port)

    children = [
      Plug.Cowboy.child_spec(
        scheme: :http,
        plug: W3cTraceContextValidation.Router,
        options: [port: http_port]
      )
    ]

    opts = [strategy: :one_for_one, name: W3cTraceContextValidation.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
