defmodule ObanExample.Application do
  use Application

  def start(_type, _args) do
    config = [
      notifier: Oban.Notifiers.PG,
      testing: :inline
    ]

    children = [{Oban, config}]

    opts = [strategy: :one_for_one, name: ObanExample.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
