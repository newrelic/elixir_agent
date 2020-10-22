defmodule MetricTest do
  use ExUnit.Case

  test "custom metrics" do
    TestHelper.restart_harvest_cycle(NewRelic.Harvest.Collector.Metric.HarvestCycle)

    NewRelic.report_custom_metric("Foo/Bar", 100)
    NewRelic.report_custom_metric("Foo/Bar", 50)

    metrics = TestHelper.gather_harvest(NewRelic.Harvest.Collector.Metric.Harvester)

    [_, [count, value, _, min, max, _]] =
      TestHelper.find_metric(metrics, "Custom/Foo/Bar", 2)

    assert count == 2
    assert value == 150.0
    assert max == 100.0
    assert min == 50.0

    TestHelper.pause_harvest_cycle(NewRelic.Harvest.Collector.Metric.HarvestCycle)
  end
end
