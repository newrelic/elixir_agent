defmodule NewRelic.Application do
  use Application

  @moduledoc false

  def start(_type, _args) do
    import Supervisor.Spec

    NewRelic.Init.run()

    children = [
      worker(NewRelic.Logger, []),
      supervisor(NewRelic.AlwaysOnSupervisor, []),
      supervisor(NewRelic.EnabledSupervisor, [[enabled: NewRelic.Config.enabled?()]]),
      worker(NewRelic.GracefulShutdown, [], shutdown: 30_000)
    ]

    opts = [strategy: :one_for_one, name: NewRelic.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
