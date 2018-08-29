defmodule NewRelic.Harvest.Collector.HarvesterSupervisor do
  use Supervisor

  @moduledoc false

  def start_link(harvester: harvester, name: name) do
    Supervisor.start_link(__MODULE__, harvester, name: name)
  end

  def init(harvester) do
    children = [worker(harvester, [])]
    supervise(children, strategy: :simple_one_for_one, restart: :temporary, max_restarts: 10)
  end
end
