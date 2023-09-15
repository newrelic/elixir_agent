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

  test "gauge dimensional metric is updated" do
    TestHelper.restart_harvest_cycle(
      NewRelic.Harvest.TelemetrySdk.DimensionalMetrics.HarvestCycle
    )

    NewRelic.report_dimensional_metric(:gauge, "mem_percent.foo_baz", 10, %{cpu: 1000})
    NewRelic.report_dimensional_metric(:gauge, "mem_percent.foo_baz", 40, %{cpu: 1000})
    NewRelic.report_dimensional_metric(:gauge, "mem_percent.foo_baz", 90, %{cpu: 1000})

    [%{metrics: metrics_map}] =
      TestHelper.gather_harvest(NewRelic.Harvest.TelemetrySdk.DimensionalMetrics.Harvester)

    metrics = Map.values(metrics_map)

    assert length(metrics) == 1
    [metric] = metrics
    assert metric.name == "mem_percent.foo_baz"
    assert metric.type == :gauge
    assert metric.value == 90

    TestHelper.pause_harvest_cycle(NewRelic.Harvest.TelemetrySdk.DimensionalMetrics.HarvestCycle)
  end

  test "count dimensional metric is updated" do
    TestHelper.restart_harvest_cycle(
      NewRelic.Harvest.TelemetrySdk.DimensionalMetrics.HarvestCycle
    )

    NewRelic.report_dimensional_metric(:count, "OOM", 1, %{cpu: 1000})
    NewRelic.report_dimensional_metric(:count, "OOM", 1, %{cpu: 1000})
    NewRelic.report_dimensional_metric(:count, "OOM", 2, %{cpu: 1000})

    [%{metrics: metrics_map}] =
      TestHelper.gather_harvest(NewRelic.Harvest.TelemetrySdk.DimensionalMetrics.Harvester)

    metrics = Map.values(metrics_map)

    assert length(metrics) == 1
    [metric] = metrics
    assert metric.name == "OOM"
    assert metric.type == :count
    assert metric.value == 4

    TestHelper.pause_harvest_cycle(NewRelic.Harvest.TelemetrySdk.DimensionalMetrics.HarvestCycle)
  end

  test "summary dimensional metric is updated" do
    TestHelper.restart_harvest_cycle(
      NewRelic.Harvest.TelemetrySdk.DimensionalMetrics.HarvestCycle
    )

    NewRelic.report_dimensional_metric(:summary, "duration", 40.5, %{cpu: 1000})
    NewRelic.report_dimensional_metric(:summary, "duration", 20.5, %{cpu: 1000})
    NewRelic.report_dimensional_metric(:summary, "duration", 9.5, %{cpu: 1000})
    NewRelic.report_dimensional_metric(:summary, "duration", 55.5, %{cpu: 1000})

    [%{metrics: metrics_map}] =
      TestHelper.gather_harvest(NewRelic.Harvest.TelemetrySdk.DimensionalMetrics.Harvester)

    metrics = Map.values(metrics_map)

    assert length(metrics) == 1
    [metric] = metrics
    assert metric.name == "duration"
    assert metric.type == :summary
    assert metric.value.sum == 126
    assert metric.value.min == 9.5
    assert metric.value.max == 55.5
    assert metric.value.count == 4

    TestHelper.pause_harvest_cycle(NewRelic.Harvest.TelemetrySdk.DimensionalMetrics.HarvestCycle)
  end
end
