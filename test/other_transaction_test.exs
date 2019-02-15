defmodule OtherTransactionTest do
  use ExUnit.Case
  alias NewRelic.Harvest.Collector

  setup do
    System.put_env("NEW_RELIC_HARVEST_ENABLED", "true")
    System.put_env("NEW_RELIC_LICENSE_KEY", "foo")
    send(NewRelic.DistributedTrace.BackoffSampler, :reset)

    on_exit(fn ->
      System.delete_env("NEW_RELIC_HARVEST_ENABLED")
      System.delete_env("NEW_RELIC_LICENSE_KEY")
    end)

    :ok
  end

  defmodule External do
    use NewRelic.Tracer
    @trace {:call, category: :external}
    def call, do: :make_request
  end

  test "reports Other Transactions" do
    TestHelper.restart_harvest_cycle(Collector.TransactionEvent.HarvestCycle)
    TestHelper.restart_harvest_cycle(Collector.TransactionTrace.HarvestCycle)
    TestHelper.restart_harvest_cycle(Collector.Metric.HarvestCycle)
    TestHelper.restart_harvest_cycle(Collector.SpanEvent.HarvestCycle)

    Task.async(fn ->
      NewRelic.start_transaction("TransactionCategory", "MyTaskName")
      NewRelic.add_attributes(other: "transaction")
      External.call()

      Task.async(fn ->
        Process.sleep(100)
      end)
      |> Task.await()
    end)
    |> Task.await()

    [event] = TestHelper.gather_harvest(Collector.TransactionEvent.Harvester)

    [
      %{name: name},
      %{
        other: "transaction",
        duration_ms: duration_ms,
        start_time: start_time,
        end_time: end_time,
        traceId: _,
        guid: _
      }
    ] = event

    assert name == "OtherTransaction/TransactionCategory/MyTaskName"
    assert end_time - start_time == duration_ms

    [_trace] = TestHelper.gather_harvest(Collector.TransactionTrace.Harvester)

    metrics = TestHelper.gather_harvest(Collector.Metric.Harvester)
    assert TestHelper.find_metric(metrics, "OtherTransaction/all")
    assert TestHelper.find_metric(metrics, "OtherTransaction/TransactionCategory/MyTaskName")

    assert TestHelper.find_metric(metrics, "External/OtherTransactionTest.External.call/all")
    assert TestHelper.find_metric(metrics, "External/allOther")

    span_events = TestHelper.gather_harvest(Collector.SpanEvent.Harvester)
    assert length(span_events) == 3

    TestHelper.pause_harvest_cycle(Collector.TransactionEvent.HarvestCycle)
    TestHelper.pause_harvest_cycle(Collector.TransactionTrace.HarvestCycle)
    TestHelper.pause_harvest_cycle(Collector.Metric.HarvestCycle)
    TestHelper.pause_harvest_cycle(Collector.SpanEvent.HarvestCycle)
  end

  @tag :capture_log
  test "Error in Other Transaction" do
    TestHelper.restart_harvest_cycle(Collector.ErrorTrace.HarvestCycle)
    start_supervised({Task.Supervisor, name: TestSupervisor})

    {:exit, {_exception, _stacktrace}} =
      Task.Supervisor.async_nolink(TestSupervisor, fn ->
        NewRelic.start_transaction("Task", "FailingTask")
        Process.sleep(100)
        raise "FAIL"
      end)
      |> Task.yield()

    [trace] = TestHelper.gather_harvest(Collector.ErrorTrace.Harvester)

    assert [
             _ts,
             name,
             "(RuntimeError) FAIL",
             _,
             _,
             _
           ] = trace

    assert name =~ "OtherTransaction"

    TestHelper.pause_harvest_cycle(Collector.ErrorTrace.HarvestCycle)
  end
end
