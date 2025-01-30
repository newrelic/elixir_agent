defmodule NewRelic.Harvest.TelemetrySdk.Supervisor do
  use Supervisor

  @moduledoc false

  alias NewRelic.Harvest
  alias NewRelic.Harvest.TelemetrySdk

  def start_link(_) do
    Supervisor.start_link(__MODULE__, [])
  end

  def init(_) do
    children = [
      data_supervisor(TelemetrySdk.Logs, :logs_harvest_cycle),
      data_supervisor(TelemetrySdk.Spans, :spans_harvest_cycle),
      data_supervisor(TelemetrySdk.DimensionalMetrics, :dimensional_metrics_harvest_cycle)
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end

  defp data_supervisor(namespace, key) do
    Supervisor.child_spec(
      {Harvest.DataSupervisor, [namespace: namespace, key: key, lookup_module: TelemetrySdk.Config]},
      id: make_ref()
    )
  end
end
