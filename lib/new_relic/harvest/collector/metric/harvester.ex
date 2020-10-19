defmodule NewRelic.Harvest.Collector.Metric.Harvester do
  use GenServer

  @moduledoc false

  alias NewRelic.Harvest
  alias NewRelic.Harvest.Collector
  alias NewRelic.Metric.MetricData

  def start_link(_) do
    GenServer.start_link(__MODULE__, [])
  end

  def init(_) do
    {:ok,
     %{
       start_time: System.system_time(),
       start_time_mono: System.monotonic_time(),
       end_time_mono: nil,
       metrics: %{}
     }}
  end

  # API

  def report_custom_metric(name, value),
    do: report_metric({:custom, name}, count: 1, value: value)

  def report_metric(identifier, values),
    do:
      Collector.Metric.HarvestCycle
      |> Harvest.HarvestCycle.current_harvester()
      |> GenServer.cast({:report, MetricData.transform(identifier, values)})

  def gather_harvest,
    do:
      Collector.Metric.HarvestCycle
      |> Harvest.HarvestCycle.current_harvester()
      |> GenServer.call(:gather_harvest)

  # Server

  def handle_cast(_late_msg, :completed), do: {:noreply, :completed}

  def handle_cast({:report, report_metrics}, state) do
    metrics =
      report_metrics
      |> List.wrap()
      |> Enum.reduce(state.metrics, fn %{name: name, scope: scope} = metric, acc ->
        Map.update(acc, {name, scope}, metric, fn existing ->
          NewRelic.Metric.merge(existing, metric)
        end)
      end)

    {:noreply, %{state | metrics: metrics}}
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
    NewRelic.report_metric({:supportability, "MetricData"}, harvest_size: harvest_size)
    NewRelic.log(:debug, "Completed Metric harvest - size: #{harvest_size}")
  end

  defp build_metric_data(metrics) do
    metrics
    |> Map.values()
    |> Enum.map(&encode/1)
  end

  def encode(%NewRelic.Metric{name: name, scope: scope} = m) do
    [
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
end
