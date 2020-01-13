defmodule NewRelic.TelemetrySupervisor do
  use Supervisor

  @moduledoc false

  def start_link do
    Supervisor.start_link(__MODULE__, [])
  end

  def init(_) do
    children = [
      supervisor(NewRelic.Telemetry.EctoSupervisor, [])
    ]

    supervise(children, strategy: :one_for_one)
  end
end
