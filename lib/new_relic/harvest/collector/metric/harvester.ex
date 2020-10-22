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

  def handle_cast({:report, metrics}, state) do
    {:noreply, %{state | metrics: merge(metrics, state)}}
  end

  def handle_call(_late_msg, _from, :completed), do: {:reply, :completed, :completed}

  def handle_call(:send_harvest, _from, state) do
    send_harvest(%{state | end_time_mono: System.monotonic_time()})
    {:reply, :ok, :completed}
  end

  def handle_call(:gather_harvest, _from, state) do
    {:reply, build_metric_data(state.metrics), state}
  end

  def merge(metrics, state) do
    metrics
    |> List.wrap()
    |> Enum.reduce(state.metrics, &merge_metric/2)
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
    Enum.map(metrics, &encode/1)
  end

  @size 6
  @call_count 1
  @total_call_time 2
  @total_exclusive_time 3
  @min_call_time 4
  @max_call_time 5
  @sum_of_squares 6

  defp merge_metric(metric, metrics_acc) do
    case Map.get(metrics_acc, {metric.name, metric.scope}) do
      nil ->
        counter = :counters.new(@size, [])

        :counters.add(counter, @call_count, round(metric.call_count))
        :counters.add(counter, @total_call_time, int(metric.total_call_time))
        :counters.add(counter, @total_exclusive_time, int(metric.total_exclusive_time))
        :counters.add(counter, @min_call_time, int(metric.min_call_time))
        :counters.add(counter, @max_call_time, int(metric.max_call_time))
        :counters.add(counter, @sum_of_squares, int(metric.sum_of_squares))

        Map.put(metrics_acc, {metric.name, metric.scope}, counter)

      counter ->
        :counters.add(counter, @call_count, round(metric.call_count))
        :counters.add(counter, @total_call_time, int(metric.total_call_time))
        :counters.add(counter, @total_exclusive_time, int(metric.total_exclusive_time))

        if int(metric.min_call_time) < :counters.get(counter, @min_call_time),
          do: :counters.put(counter, @min_call_time, int(metric.max_call_time))

        if int(metric.max_call_time) > :counters.get(counter, @max_call_time),
          do: :counters.put(counter, @max_call_time, int(metric.max_call_time))

        :counters.add(counter, @sum_of_squares, int(metric.sum_of_squares))

        metrics_acc
    end
  end

  defp encode({{name, scope}, metric}) do
    [
      %{name: to_string(name), scope: to_string(scope)},
      [
        :counters.get(metric, @call_count),
        unint(:counters.get(metric, @total_call_time)),
        unint(:counters.get(metric, @total_exclusive_time)),
        unint(:counters.get(metric, @min_call_time)),
        unint(:counters.get(metric, @max_call_time)),
        unint(:counters.get(metric, @sum_of_squares))
      ]
    ]
  end

  @precision 1_000
  defp int(val), do: round(val * @precision)
  defp unint(val), do: val / @precision
end
