defmodule NewRelic.EnabledSupervisor do
  use Supervisor

  # This Supervisor starts processes that we
  # only start if the agent is enabled

  @moduledoc false

  def start_link(_) do
    Supervisor.start_link(__MODULE__, :ok)
  end

  def init(:ok) do
    children = [
      supervisor(NewRelic.Harvest.Supervisor, []),
      supervisor(NewRelic.Telemetry.Supervisor, []),
      supervisor(NewRelic.Sampler.Supervisor, []),
      supervisor(NewRelic.Error.Supervisor, []),
      supervisor(NewRelic.Aggregate.Supervisor, [])
    ]

    supervise(children, strategy: :one_for_one)
  end
end
