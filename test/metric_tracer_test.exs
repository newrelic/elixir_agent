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

    @trace {:db, category: :datastore}
    def db do
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

    assert_metric(metrics, "External/MetricTracerTest.MetricTraced.query/all", 2)
    assert_metric(metrics, "External/MetricTracerTest.MetricTraced.custom_name:special/all", 2)
  end

  test "Datastore metrics" do
    MetricTraced.db()

    metrics = TestHelper.gather_harvest(Collector.Metric.Harvester)

    assert_metric(metrics, "Datastore/statement/Postgres/MetricTracerTest.MetricTraced.db")
    assert_metric(metrics, "Datastore/Postgres/all")
  end

  def assert_metric(metrics, name, call_count \\ 1) do
    assert [_metric_identity, [^call_count, _, _, _, _, _]] = find_metric_by_name(metrics, name)
  end

  def find_metric_by_name(metrics, name),
    do: Enum.find(metrics, fn [%{name: n}, _] -> n == name end)
end
