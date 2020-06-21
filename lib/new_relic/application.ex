defmodule NewRelic.Application do
  use Application

  @moduledoc false

  def start(_type, _args) do
    NewRelic.Init.run()

    children = [
      NewRelic.Logger,
      NewRelic.AlwaysOnSupervisor,
      NewRelic.EnabledSupervisorManager,
      NewRelic.TelemetrySupervisor,
      NewRelic.GracefulShutdown
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: NewRelic.Supervisor)
  end
end
