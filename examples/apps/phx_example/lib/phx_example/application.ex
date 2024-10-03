defmodule PhxExample.Application do
  @moduledoc false

  use Application

  def start(_type, _args) do
    children = [
      {Phoenix.PubSub, name: PhxExample.PubSub},
      PhxExampleWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: PhxExample.Supervisor]
    Supervisor.start_link(children, opts)
  end

  def config_change(changed, _new, removed) do
    PhxExampleWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
