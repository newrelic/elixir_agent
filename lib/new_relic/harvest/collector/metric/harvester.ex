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

  def increment_custom_metric(name, count),
    do: report_metric({:custom, name}, count: count)

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

  defp merge(metrics, state) do
    metrics
    |> List.wrap()
    |> Enum.reduce(state.metrics, &merge_metric/2)
  end

  defp send_harvest(state) do
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

  defp log_harvest(harvest_size) do
    NewRelic.report_metric({:supportability, "MetricData"}, harvest_size: harvest_size)
    NewRelic.log(:debug, "Completed Metric harvest - size: #{harvest_size}")
  end

  defp build_metric_data(metrics) do
    Enum.map(metrics, &build/1)
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
        counter = new(@size, [])

        add(counter, @call_count, round(metric.call_count))
        add(counter, @total_call_time, encode(metric.total_call_time))
        add(counter, @total_exclusive_time, encode(metric.total_exclusive_time))
        add(counter, @min_call_time, encode(metric.min_call_time))
        add(counter, @max_call_time, encode(metric.max_call_time))
        add(counter, @sum_of_squares, encode(metric.sum_of_squares))

        Map.put(metrics_acc, {metric.name, metric.scope}, counter)

      counter ->
        add(counter, @call_count, round(metric.call_count))
        add(counter, @total_call_time, encode(metric.total_call_time))
        add(counter, @total_exclusive_time, encode(metric.total_exclusive_time))

        if metric.min_call_time < decode(get(counter, @min_call_time)),
          do: put(counter, @min_call_time, encode(metric.max_call_time))

        if metric.max_call_time > decode(get(counter, @max_call_time)),
          do: put(counter, @max_call_time, encode(metric.max_call_time))

        add(counter, @sum_of_squares, encode(metric.sum_of_squares))

        metrics_acc
    end
  end

  defp build({{name, scope}, counter}) do
    [
      %{name: to_string(name), scope: to_string(scope)},
      [
        get(counter, @call_count),
        decode(get(counter, @total_call_time)),
        decode(get(counter, @total_exclusive_time)),
        decode(get(counter, @min_call_time)),
        decode(get(counter, @max_call_time)),
        decode(get(counter, @sum_of_squares))
      ]
    ]
  end

  @compile {:inline, new: 2, add: 3, put: 3, get: 2}
  defp new(size, opts), do: :counters.new(size, opts)
  defp add(counter, index, value), do: :counters.add(counter, index, value)
  defp put(counter, index, value), do: :counters.put(counter, index, value)
  defp get(counter, index), do: :counters.get(counter, index)

  # counters store integers, so we encode values
  # into integers keeping 4 decimal places of precision
  @precision 10_000
  @compile {:inline, encode: 1, decode: 1}
  defp encode(val), do: round(val * @precision)
  defp decode(val), do: val / @precision
end
