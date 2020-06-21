defmodule NewRelic.Harvest.Supervisor do
  use Supervisor
  alias NewRelic.Harvest.Collector

  @moduledoc false

  @all_harvesters [
    Collector.Metric.HarvestCycle,
    Collector.TransactionTrace.HarvestCycle,
    Collector.TransactionEvent.HarvestCycle,
    Collector.SpanEvent.HarvestCycle,
    Collector.TransactionErrorEvent.HarvestCycle,
    Collector.CustomEvent.HarvestCycle,
    Collector.ErrorTrace.HarvestCycle
  ]

  def start_link(_) do
    Supervisor.start_link(__MODULE__, [])
  end

  def init(_) do
    children = [
      {Task.Supervisor, name: Collector.TaskSupervisor},
      Collector.Supervisor
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def manual_shutdown do
    if NewRelic.Config.enabled?() do
      @all_harvesters
      |> Enum.map(
        &Task.async(fn ->
          Collector.HarvestCycle.manual_shutdown(&1)
        end)
      )
      |> Enum.map(&Task.await/1)
    end
  end
end
