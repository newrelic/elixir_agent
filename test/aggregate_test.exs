defmodule AggregateTest do
  use ExUnit.Case

  alias NewRelic.Aggregate
  alias NewRelic.Harvest.Collector

  test "Aggregate metrics" do
    metric = %Aggregate{
      meta: %{key: "value", foo: "bar"},
      values: %{duration: 5, call_count: 2, foo: 1}
    }

    values = %{duration: 3, call_count: 1, bar: 1}

    result = Aggregate.merge(metric, values)
    assert result.meta == %{key: "value", foo: "bar"}
    assert result.values == %{duration: 8, call_count: 3, foo: 1, bar: 1}
  end

  test "Annotate metrics w/ averages" do
    metric = %Aggregate{meta: %{call_count: true}, values: %{duration: 10, call_count: 2, foo: 1}}

    annotated = Aggregate.annotate(metric)
    assert annotated.duration == 10
    assert annotated.avg_duration == 5
  end

  test "unless there's no call count" do
    metric = %Aggregate{meta: %{call_count: false}, values: %{duration: 10, foo: 1}}

    annotated = Aggregate.annotate(metric)
    assert annotated[:avg_duration] == nil
  end

  test "Aggregate.Reporter collects aggregated metrics" do
    TestHelper.restart_harvest_cycle(Collector.CustomEvent.HarvestCycle)

    NewRelic.report_aggregate(%{meta: "data"}, %{duration: 5})
    NewRelic.report_aggregate(%{meta: "data"}, %{duration: 5})
    NewRelic.report_aggregate(%{meta: "data"}, %{duration: 5})

    TestHelper.trigger_report(NewRelic.Aggregate.Reporter)

    events = TestHelper.gather_harvest(Collector.CustomEvent.Harvester)

    assert Enum.find(events, fn [_, event, _] ->
             event[:category] == :Metric && event[:meta] == "data" && event[:duration] == 15
           end)
  end
end
