defmodule MetricErrorTest do
  use ExUnit.Case
  alias NewRelic.Harvest.Collector

  defmodule CustomError do
    defexception [:message, :expected]
  end

  @tag :capture_log
  test "Catch and record error Metric for unexpected errors" do
    TestHelper.restart_harvest_cycle(Collector.Metric.HarvestCycle)
    start_supervised({Task.Supervisor, name: TestSupervisor})

    {:exit, {_exception, _stacktrace}} =
      Task.Supervisor.async_nolink(TestSupervisor, fn ->
        raise "BAD_TIMES"
      end)
      |> Task.yield()

    {:exit, {_exception, _stacktrace}} =
      Task.Supervisor.async_nolink(TestSupervisor, fn ->
        raise "BAD_TIMES"
      end)
      |> Task.yield()

    {:exit, {_exception, _stacktrace}} =
      Task.Supervisor.async_nolink(TestSupervisor, fn ->
        raise CustomError, message: "BAD_TIMES", expected: true
      end)
      |> Task.yield()

    metrics = TestHelper.gather_harvest(Collector.Metric.Harvester)

    assert_metric(metrics, "Errors/all", 2)

    TestHelper.pause_harvest_cycle(Collector.Metric.HarvestCycle)
  end

  def assert_metric(metrics, name, call_count \\ 1) do
    assert [_metric_identity, [^call_count, _, _, _, _, _]] = find_metric_by_name(metrics, name)
  end

  def find_metric_by_name(metrics, name),
    do: Enum.find(metrics, fn [%{name: n}, _] -> n == name end)
end
