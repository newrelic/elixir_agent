defmodule NewRelic.AlwaysOnSupervisor do
  use Supervisor

  @moduledoc false

  def start_link do
    Supervisor.start_link(__MODULE__, [])
  end

  def init(_) do
    children = [
      worker(NewRelic.Harvest.Collector.AgentRun, []),
      worker(NewRelic.Harvest.Collector.HarvesterStore, []),
      supervisor(NewRelic.DistributedTrace.Supervisor, []),
      supervisor(NewRelic.Transaction.Supervisor, [])
    ]

    supervise(children, strategy: :one_for_one)
  end
end
