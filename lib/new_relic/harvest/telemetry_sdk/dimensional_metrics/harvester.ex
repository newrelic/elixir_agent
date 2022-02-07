defmodule NewRelic.Harvest.TelemetrySdk.DimensionalMetrics.Harvester do
  use GenServer

  @moduledoc false

  alias NewRelic.Harvest
  alias NewRelic.Harvest.TelemetrySdk

  @interval_ms TelemetrySdk.Config.lookup(:dimensional_metrics_harvest_cycle)

  @valid_types [:count, :gauge, :summary]

  def start_link(_) do
    GenServer.start_link(__MODULE__, [])
  end

  def init(_) do
    {:ok,
     %{
       start_time_ms: System.system_time(:millisecond),
       metrics: %{},
       attributes: %{}
     }}
  end

  # API

  @spec report_dimensional_metric(:count | :gauge | :summary, atom() | binary(), any, map()) ::
          :ok
  def report_dimensional_metric(type, name, value, attributes) when type in @valid_types do
    TelemetrySdk.DimensionalMetrics.HarvestCycle
    |> Harvest.HarvestCycle.current_harvester()
    |> GenServer.cast({:report, %{type: type, name: name, value: value, attributes: attributes}})
  end

  def gather_harvest,
    do:
      TelemetrySdk.DimensionalMetrics.HarvestCycle
      |> Harvest.HarvestCycle.current_harvester()
      |> GenServer.call(:gather_harvest)

  # do not accept more report messages when harvest has already been reported
  def handle_cast(_late_msg, :completed), do: {:noreply, :completed}

  def handle_cast({:report, metric}, state) do
    # convert metric to tuple key
    key = metric_key(metric)

    {:noreply,
     %{
       state
       | metrics: merge(state.metrics, key, metric),
         attributes: Map.put_new(state.attributes, key, metric[:attributes])
     }}
  end

  # do not resend metrics when harvest has already been reported
  def handle_call(_late_msg, _from, :completed), do: {:reply, :completed, :completed}

  def handle_call(:send_harvest, _from, state) do
    send_harvest(state)
    {:reply, :ok, :completed}
  end

  def handle_call(:gather_harvest, _from, state) do
    {:reply, build_dimensional_metric_data(state.metrics, state), state}
  end

  # Helpers

  defp merge(metrics, key, metric) do
    # put or update counter
    Map.update(metrics, key, default(metric), &update(&1, metric))
  end

  @size 1
  defp default(metric) do
    @size
    |> :counters.new([])
    |> update(metric)
  end

  @index 1
  defp update(counters, metric) do
    :counters.add(counters, @index, metric[:value])
  end

  @spec metric_key(%{
          required(:type) => atom(),
          required(:name) => binary(),
          required(:attributes) => map()
        }) :: {atom(), binary(), non_neg_integer()}
  defp metric_key(%{type: type, name: name, attributes: attributes}) do
    {type, name, :erlang.phash2(attributes)}
  end

  defp send_harvest(state) do
    TelemetrySdk.API.log(build_dimensional_metric_data(state.metrics, state))
    log_harvest(length(state.metrics))
  end

  defp log_harvest(harvest_size) do
    NewRelic.log(
      :debug,
      "Completed TelemetrySdk.DimensionalMetrics harvest - size: #{harvest_size}"
    )
  end

  defp build_dimensional_metric_data(metrics, state) do
    [
      %{
        metrics: metrics,
        common: common(state)
      }
    ]
  end

  defp common(%{start_time_ms: start_time_ms}) do
    %{"timestamp" => start_time_ms, "interval.ms" => @interval_ms}
  end
end
