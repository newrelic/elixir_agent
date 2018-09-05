defmodule NewRelic.Harvest.Collector.Supervisor do
  use Supervisor

  @moduledoc false

  alias NewRelic.Harvest.Collector

  def start_link do
    Supervisor.start_link(__MODULE__, [])
  end

  def init(_) do
    children = [
      worker(Collector.AgentRun, []),
      data_supervisor(Collector.Metric, :data_report_period),
      data_supervisor(Collector.TransactionTrace, :data_report_period),
      data_supervisor(Collector.ErrorTrace, :data_report_period),
      data_supervisor(Collector.TransactionEvent, :transaction_event_harvest_cycle),
      data_supervisor(Collector.TransactionErrorEvent, :error_event_harvest_cycle),
      data_supervisor(Collector.CustomEvent, :custom_event_harvest_cycle),
      data_supervisor(Collector.SpanEvent, :span_event_harvest_cycle)
    ]

    supervise(children, strategy: :one_for_all)
  end

  def data_supervisor(namespace, key) do
    supervisor(Collector.DataSupervisor, [[namespace: namespace, key: key]], id: make_ref())
  end
end
