defmodule OtherTransactionTest do
  use ExUnit.Case
  alias NewRelic.Harvest.Collector

  test "reports Other Transactions" do
    TestHelper.restart_harvest_cycle(Collector.TransactionEvent.HarvestCycle)
    TestHelper.restart_harvest_cycle(Collector.TransactionTrace.HarvestCycle)
    TestHelper.restart_harvest_cycle(NewRelic.Harvest.Collector.Metric.HarvestCycle)

    Task.async(fn ->
      NewRelic.start_transaction("TransactionCategory", "MyTaskName")
      NewRelic.add_attributes(other: "transaction")
      Process.sleep(100)
    end)
    |> Task.await()

    [event] = TestHelper.gather_harvest(Collector.TransactionEvent.Harvester)
    [%{name: name}, %{other: "transaction"}] = event

    assert name == "OtherTransaction/TransactionCategory/MyTaskName"

    [_trace] = TestHelper.gather_harvest(Collector.TransactionTrace.Harvester)

    metrics = TestHelper.gather_harvest(Collector.Metric.Harvester)

    assert TestHelper.find_metric(metrics, "OtherTransaction/all")
    assert TestHelper.find_metric(metrics, "OtherTransaction/TransactionCategory/MyTaskName")

    TestHelper.pause_harvest_cycle(Collector.TransactionEvent.HarvestCycle)
    TestHelper.pause_harvest_cycle(Collector.TransactionTrace.HarvestCycle)
    TestHelper.pause_harvest_cycle(NewRelic.Harvest.Collector.Metric.HarvestCycle)
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
             "OtherTransaction/Task/FailingTask",
             "(RuntimeError) FAIL",
             _,
             _,
             _
           ] = trace

    TestHelper.pause_harvest_cycle(Collector.ErrorTrace.HarvestCycle)
  end
end
