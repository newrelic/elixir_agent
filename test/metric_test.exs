defmodule MetricTest do
  use ExUnit.Case

  test "Create a Metric" do
    metric = %NewRelic.Metric{
      name: "name",
      scope: "scope",
      call_count: 2,
      max_call_time: 3.4,
      min_call_time: 0.1,
      sum_of_squares: 10,
      total_call_time: 100,
      total_exclusive_time: 90
    }

    assert metric.name == "name"
  end

  test "reduce a list of Metrics" do
    metrics = [
      %NewRelic.Metric{
        name: "name",
        scope: "scope",
        call_count: 2,
        max_call_time: 3.4,
        min_call_time: 0.1,
        sum_of_squares: 10,
        total_call_time: 100,
        total_exclusive_time: 90
      },
      %NewRelic.Metric{
        name: "name",
        scope: "scope",
        call_count: 1,
        max_call_time: 1,
        min_call_time: 1,
        sum_of_squares: 100,
        total_call_time: 5,
        total_exclusive_time: 1
      },
      %NewRelic.Metric{
        name: "name",
        scope: "scope",
        call_count: 1,
        max_call_time: 5,
        min_call_time: 0,
        sum_of_squares: 20,
        total_call_time: 2,
        total_exclusive_time: 1
      }
    ]

    aggregated = NewRelic.Metric.reduce(metrics)

    assert aggregated.call_count == 4
    assert aggregated.max_call_time == 5
    assert aggregated.min_call_time == 0.1
    assert aggregated.sum_of_squares == 130
    assert aggregated.total_call_time == 107
    assert aggregated.total_exclusive_time == 92
  end
end
