defmodule NewRelic.Application do
  use Application

  @moduledoc false

  def start(_type, _args) do
    import Supervisor.Spec

    NewRelic.Init.run()

    children = [
      NewRelic.Logger,
      NewRelic.AlwaysOnSupervisor,
      NewRelic.EnabledSupervisorManager,
      NewRelic.TelemetrySupervisor,
      NewRelic.GracefulShutdown
    ]

    opts = [strategy: :one_for_one, name: NewRelic.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
