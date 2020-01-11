defmodule NewRelic.Harvest.Collector.DataSupervisor do
  use Supervisor

  @moduledoc false

  alias NewRelic.Harvest.Collector

  def start_link(config) do
    Supervisor.start_link(__MODULE__, config)
  end

  def init(namespace: namespace, key: harvest_cycle_key) do
    harvester = Module.concat(namespace, Harvester)
    harvester_supervisor = Module.concat(namespace, HarvesterSupervisor)
    harvester_cycle = Module.concat(namespace, HarvestCycle)

    children = [
      supervisor(Collector.HarvesterSupervisor, [
        [harvester: harvester, name: harvester_supervisor]
      ]),
      worker(Collector.HarvestCycle, [
        [
          name: harvester_cycle,
          child_spec: harvester,
          harvest_cycle_key: harvest_cycle_key,
          supervisor: harvester_supervisor
        ]
      ])
    ]

    supervise(children, strategy: :one_for_one)
  end
end
