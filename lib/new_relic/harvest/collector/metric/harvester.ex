defmodule NewRelic.Harvest.Collector.Metric.Harvester do
  use GenServer

  @moduledoc false

  alias NewRelic.Harvest.Collector

  def start_link do
    GenServer.start_link(__MODULE__, [])
  end

  def init(_) do
    {:ok,
     %{
       start_time: System.system_time(),
       start_time_mono: System.monotonic_time(),
       end_time_mono: nil,
       metrics: []
     }}
  end

  # API

  def report_metric(identifier, values),
    do:
      Collector.Metric.HarvestCycle
      |> Collector.HarvestCycle.current_harvester()
      |> GenServer.cast({:report, Collector.MetricData.transform(identifier, values)})

  def gather_harvest,
    do:
      Collector.Metric.HarvestCycle
      |> Collector.HarvestCycle.current_harvester()
      |> GenServer.call(:gather_harvest)

  # Server

  def handle_cast(_late_msg, :completed), do: {:noreply, :completed}

  def handle_cast({:report, metrics}, state) when is_list(metrics) do
    {:noreply, %{state | metrics: metrics ++ state.metrics}}
  end

  def handle_cast({:report, metric}, state) do
    {:noreply, %{state | metrics: [metric | state.metrics]}}
  end

  def handle_call(_late_msg, _from, :completed), do: {:reply, :completed, :completed}

  def handle_call(:send_harvest, _from, state) do
    send_harvest(%{state | end_time_mono: System.monotonic_time()})
    {:reply, :ok, :completed}
  end

  def handle_call(:gather_harvest, _from, state) do
    {:reply, build_metric_data(state.metrics), state}
  end

  def send_harvest(state) do
    metric_data = build_metric_data(state.metrics)

    Collector.Protocol.metric_data([
      Collector.AgentRun.agent_run_id(),
      System.convert_time_unit(state.start_time, :native, :second),
      System.convert_time_unit(
        state.start_time + (state.end_time_mono - state.start_time_mono),
        :native,
        :second
      ),
      metric_data
    ])

    log_harvest(length(metric_data))
  end

  def log_harvest(harvest_size) do
    NewRelic.report_metric({:supportability, Metric}, harvest_size: harvest_size)
    NewRelic.log(:debug, "Completed Metric harvest - size: #{harvest_size}")
  end

  defp build_metric_data(metrics),
    do:
      metrics
      |> Enum.group_by(&metric_ident/1)
      |> Enum.map(&aggregate/1)
      |> Enum.map(&encode/1)

  def metric_ident(metric), do: {metric.name, metric.scope}

  def aggregate({_ident, metrics}), do: NewRelic.Metric.reduce(metrics)

  def encode(%NewRelic.Metric{name: name, scope: scope} = m),
    do: [
      %{name: to_string(name), scope: to_string(scope)},
      [
        m.call_count,
        m.total_call_time,
        m.total_exclusive_time,
        m.min_call_time,
        m.max_call_time,
        m.sum_of_squares
      ]
    ]
end
