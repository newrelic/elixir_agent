defmodule MetricTest do
  use ExUnit.Case

  test "merge two Metrics" do
    one = %NewRelic.Metric{
      name: "name",
      scope: "scope",
      call_count: 2,
      max_call_time: 3.4,
      min_call_time: 1.3,
      sum_of_squares: 10,
      total_call_time: 100,
      total_exclusive_time: 90
    }

    two = %NewRelic.Metric{
      name: "name",
      scope: "scope",
      call_count: 1,
      max_call_time: 1,
      min_call_time: 3.1,
      sum_of_squares: 100,
      total_call_time: 5,
      total_exclusive_time: 1
    }

    aggregated = NewRelic.Metric.merge(one, two)

    assert aggregated.call_count == 3
    assert aggregated.max_call_time == 3.4
    assert aggregated.min_call_time == 1.3
    assert aggregated.sum_of_squares == 110
    assert aggregated.total_call_time == 105
    assert aggregated.total_exclusive_time == 91
  end

  test "custom metrics" do
    TestHelper.restart_harvest_cycle(NewRelic.Harvest.Collector.Metric.HarvestCycle)

    NewRelic.report_custom_metric("Foo/Bar", 100)
    NewRelic.report_custom_metric("Foo/Bar", 50)

    metrics = TestHelper.gather_harvest(NewRelic.Harvest.Collector.Metric.Harvester)

    expected_count = 2
    expected_value = 150

    [_, [^expected_count, ^expected_value, _, _, _, _]] =
      TestHelper.find_metric(metrics, "Custom/Foo/Bar", expected_count)

    TestHelper.pause_harvest_cycle(NewRelic.Harvest.Collector.Metric.HarvestCycle)
  end
end
