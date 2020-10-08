defmodule NewRelic.AlwaysOnSupervisor do
  use Supervisor

  @moduledoc false

  def start_link(_) do
    Supervisor.start_link(__MODULE__, [])
  end

  def init(_) do
    children = [
      NewRelic.Harvest.Collector.AgentRun,
      NewRelic.Harvest.HarvesterStore,
      NewRelic.DistributedTrace.Supervisor,
      NewRelic.Transaction.Supervisor
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
