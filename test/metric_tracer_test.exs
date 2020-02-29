defmodule MetricTracerTest do
  use ExUnit.Case

  alias NewRelic.Harvest.Collector

  setup do
    TestHelper.restart_harvest_cycle(Collector.Metric.HarvestCycle)
    on_exit(fn -> TestHelper.pause_harvest_cycle(Collector.Metric.HarvestCycle) end)
  end

  defmodule MetricTraced do
    use NewRelic.Tracer

    @trace :fun
    def fun do
    end

    @trace :bar
    def foo do
    end

    @trace {:query, category: :external}
    def query do
    end

    @trace {:query, category: :external}
    def external_call do
      NewRelic.set_span(:http, url: "http://domain.net", method: "GET", component: "HttpClient")
    end

    @trace {:special, category: :external}
    def custom_name do
    end

    @trace :nested
    def nested do
      # duration ~ 1100
      # exclusive ~ 0
      nested_1()
    end

    @trace :nested_1
    def nested_1 do
      # duration ~ 1100
      # exclusive ~ 100
      Process.sleep(50)
      nested_2()
      Process.sleep(50)
      nested_2()
    end

    @trace :nested_2
    def nested_2 do
      # duration ~ 500
      # exclusive ~ 200
      Process.sleep(200)
      nested_3()
    end

    @trace :nested_3
    def nested_3 do
      # duration ~ 300
      # exclusive ~ 300
      Process.sleep(300)
      :done
    end
  end

  test "External metrics" do
    MetricTraced.query()
    MetricTraced.query()
    MetricTraced.custom_name()
    MetricTraced.custom_name()

    metrics = TestHelper.gather_harvest(Collector.Metric.Harvester)

    assert TestHelper.find_metric(metrics, "External/MetricTracerTest.MetricTraced.query/all", 2)

    assert TestHelper.find_metric(
             metrics,
             "External/MetricTracerTest.MetricTraced.custom_name:special/all",
             2
           )
  end

  test "External metrics use span data" do
    MetricTraced.external_call()
    MetricTraced.external_call()

    metrics = TestHelper.gather_harvest(Collector.Metric.Harvester)

    assert TestHelper.find_metric(metrics, "External/all", 2)
    assert TestHelper.find_metric(metrics, "External/domain.net/all", 2)
    assert TestHelper.find_metric(metrics, "External/domain.net/HttpClient/GET", 2)
  end

  @delta 0.05
  test "Exclusive time calculations" do
    MetricTraced.nested()

    metrics = TestHelper.gather_harvest(Collector.Metric.Harvester)

    {total, exclusive} =
      get_avg_times(metrics, "Function/MetricTracerTest.MetricTraced.nested/0", 1)

    assert_in_delta total, 1.1, @delta
    assert_in_delta exclusive, 0.0, @delta

    {total, exclusive} =
      get_avg_times(metrics, "Function/MetricTracerTest.MetricTraced.nested_1/0", 1)

    assert_in_delta total, 1.1, @delta
    assert_in_delta exclusive, 0.1, @delta

    {total, exclusive} =
      get_avg_times(metrics, "Function/MetricTracerTest.MetricTraced.nested_2/0", 2)

    assert_in_delta total, 0.5, @delta
    assert_in_delta exclusive, 0.2, @delta

    {total, exclusive} =
      get_avg_times(metrics, "Function/MetricTracerTest.MetricTraced.nested_3/0", 2)

    assert_in_delta total, 0.3, @delta
    assert_in_delta exclusive, 0.3, @delta
  end

  defp get_avg_times(metrics, name, count) do
    [_, [count, total, exclusive, _min, _max, _sq]] = TestHelper.find_metric(metrics, name, count)

    {total / count, exclusive / count}
  end
end
