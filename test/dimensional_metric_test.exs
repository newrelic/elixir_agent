defmodule DimensionalMetricTest do
  use ExUnit.Case

  test "reports dimensional metrics" do
    TestHelper.restart_harvest_cycle(
      NewRelic.Harvest.TelemetrySdk.DimensionalMetrics.HarvestCycle
    )

    NewRelic.report_dimensional_metric(:count, "memory.foo_baz", 100, %{cpu: 1000})
    NewRelic.report_dimensional_metric(:summary, "memory.foo_bar", 50, %{cpu: 2000})

    [%{common: common, metrics: metrics_map}] =
      TestHelper.gather_harvest(NewRelic.Harvest.TelemetrySdk.DimensionalMetrics.Harvester)

    metrics = Map.values(metrics_map)
    assert common["interval.ms"] > 0
    assert common["timestamp"] > 0

    assert length(metrics) == 2
    [metric1, metric2] = metrics
    assert metric1.name == "memory.foo_baz"
    assert metric1.type == :count

    assert metric2.name == "memory.foo_bar"
    assert metric2.type == :summary

    TestHelper.pause_harvest_cycle(NewRelic.Harvest.TelemetrySdk.DimensionalMetrics.HarvestCycle)
  end
end
