defmodule NewRelic.Harvest.Supervisor do
  use Supervisor
  alias NewRelic.Harvest.Collector

  @moduledoc false

  def start_link do
    Supervisor.start_link(__MODULE__, [])
  end

  def init(_) do
    children = [
      worker(Collector.HarvesterStore, []),
      supervisor(Task.Supervisor, [[name: Collector.TaskSupervisor]]),
      supervisor(Collector.Supervisor, [])
    ]

    supervise(children, strategy: :one_for_one)
  end

  def manual_shutdown do
    if NewRelic.Config.enabled?() do
      [
        Collector.Metric.HarvestCycle,
        Collector.TransactionTrace.HarvestCycle,
        Collector.TransactionEvent.HarvestCycle,
        Collector.SpanEvent.HarvestCycle,
        Collector.TransactionErrorEvent.HarvestCycle,
        Collector.CustomEvent.HarvestCycle,
        Collector.ErrorTrace.HarvestCycle
      ]
      |> Enum.map(&Collector.HarvestCycle.manual_shutdown/1)
    end
  end
end
