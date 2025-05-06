defmodule MetricHarvesterTest do
  use ExUnit.Case

  alias NewRelic.Harvest
  alias NewRelic.Harvest.Collector

  test "Harvester - collect and aggregate some metrics" do
    {:ok, harvester} =
      DynamicSupervisor.start_child(
        Collector.Metric.HarvesterSupervisor,
        Collector.Metric.Harvester
      )

    metric1 = %NewRelic.Metric{name: "TestMetric", call_count: 1, total_call_time: 100}
    metric2 = %NewRelic.Metric{name: "TestMetric", call_count: 1, total_call_time: 50}
    GenServer.cast(harvester, {:report, metric1})
    GenServer.cast(harvester, {:report, metric2})

    # Verify that the metric is encoded as the collector desires
    metrics = GenServer.call(harvester, :gather_harvest)
    [metric] = metrics
    [metric_ident, metric_values] = metric
    assert metric_ident == %{name: "TestMetric", scope: ""}
    assert metric_values == [2, 150, 0, 0, 0, 0]

    # Verify that the Harvester shuts down w/o error
    Process.monitor(harvester)
    Harvest.HarvestCycle.send_harvest(Collector.Metric.HarvesterSupervisor, harvester)
    assert_receive {:DOWN, _ref, _, ^harvester, :shutdown}, 1000
  end

  test "harvest cycle" do
    TestHelper.run_with(:application_config, data_report_period: 300)
    TestHelper.restart_harvest_cycle(Collector.Metric.HarvestCycle)

    first = Harvest.HarvestCycle.current_harvester(Collector.Metric.HarvestCycle)
    Process.monitor(first)

    # Wait until harvest swap
    assert_receive {:DOWN, _ref, _, ^first, :shutdown}, 1000

    second = Harvest.HarvestCycle.current_harvester(Collector.Metric.HarvestCycle)
    Process.monitor(second)

    refute first == second
    assert Process.alive?(second)

    # Ensure the last harvester has shut down
    assert_receive {:DOWN, _ref, _, ^second, :shutdown}, 1000
  end

  test "Ignore late reports" do
    TestHelper.restart_harvest_cycle(Collector.Metric.HarvestCycle)

    harvester =
      Collector.Metric.HarvestCycle
      |> Harvest.HarvestCycle.current_harvester()

    assert :ok == GenServer.call(harvester, :send_harvest)

    GenServer.cast(harvester, {:report, :late_msg})

    assert :completed == GenServer.call(harvester, :send_harvest)
  end
end
