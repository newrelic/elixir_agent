defmodule NewRelic.Harvest.Supervisor do
  use Supervisor

  alias NewRelic.Harvest

  @moduledoc false

  @all_harvesters [
    Harvest.Collector.Metric.HarvestCycle,
    Harvest.Collector.TransactionTrace.HarvestCycle,
    Harvest.Collector.TransactionEvent.HarvestCycle,
    Harvest.Collector.SpanEvent.HarvestCycle,
    Harvest.Collector.TransactionErrorEvent.HarvestCycle,
    Harvest.Collector.CustomEvent.HarvestCycle,
    Harvest.Collector.ErrorTrace.HarvestCycle,
    Harvest.TelemetrySdk.Logs.HarvestCycle,
    Harvest.TelemetrySdk.Spans.HarvestCycle,
    Harvest.TelemetrySdk.DimensionalMetrics.HarvestCycle
  ]

  def start_link(_) do
    Supervisor.start_link(__MODULE__, [])
  end

  def init(_) do
    children = [
      {Task.Supervisor, name: Harvest.TaskSupervisor},
      Harvest.Collector.Supervisor,
      Harvest.TelemetrySdk.Supervisor
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def manual_shutdown do
    if NewRelic.Config.enabled?() do
      @all_harvesters
      |> Enum.map(
        &Task.async(fn ->
          Harvest.HarvestCycle.manual_shutdown(&1)
        end)
      )
      |> Enum.map(&Task.await/1)
    end
  end
end
