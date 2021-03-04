defmodule NewRelic.Application do
  use Application

  @moduledoc false

  def start(_type, _args) do
    NewRelic.Init.run()
    NewRelic.SignalHandler.start()

    children = [
      NewRelic.Logger,
      NewRelic.AlwaysOnSupervisor,
      NewRelic.EnabledSupervisorManager,
      NewRelic.Telemetry.Supervisor,
      NewRelic.GracefulShutdown
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: NewRelic.Supervisor)
  end
end
