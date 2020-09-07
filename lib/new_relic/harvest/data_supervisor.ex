defmodule NewRelic.Harvest.DataSupervisor do
  use Supervisor

  @moduledoc false

  alias NewRelic.Harvest

  def start_link(config) do
    Supervisor.start_link(__MODULE__, config)
  end

  def init(namespace: namespace, key: harvest_cycle_key, lookup_module: lookup_module) do
    harvester = Module.concat(namespace, Harvester)
    harvester_supervisor = Module.concat(namespace, HarvesterSupervisor)
    harvester_cycle = Module.concat(namespace, HarvestCycle)

    children = [
      {Harvest.HarvesterSupervisor, harvester: harvester, name: harvester_supervisor},
      {Harvest.HarvestCycle,
       name: harvester_cycle,
       child_spec: harvester,
       harvest_cycle_key: harvest_cycle_key,
       supervisor: harvester_supervisor,
       lookup_module: lookup_module}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
