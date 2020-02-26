defmodule MetricTracerTest do
  use ExUnit.Case

  alias NewRelic.Harvest.Collector

  setup_all do
    unless System.get_env("NR_INT_TEST") do
      start_supervised({NewRelic.EnabledSupervisor, enabled: true})
      :ok
    end
  end

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
end
