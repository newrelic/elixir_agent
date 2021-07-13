defmodule OtherTransactionTest do
  use ExUnit.Case

  alias NewRelic.Harvest.Collector
  alias NewRelic.Harvest.TelemetrySdk

  setup do
    reset_config = TestHelper.update(:nr_config, license_key: "dummy_key", harvest_enabled: true)
    send(NewRelic.DistributedTrace.BackoffSampler, :reset)

    on_exit(fn ->
      reset_config.()
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
        # min duration for collecting trace
        Process.sleep(50)
      end)
      |> Task.await()

      Process.sleep(10)
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
        total_time_s: total_time_s,
        traceId: _,
        guid: _
      }
    ] = event

    assert name == "OtherTransaction/TransactionCategory/MyTaskName"
    assert_in_delta end_time - start_time, duration_ms, 1

    assert duration_ms >= 60
    assert total_time_s >= (60 + 50) / 1000

    [_trace] = TestHelper.gather_harvest(Collector.TransactionTrace.Harvester)

    metrics = TestHelper.gather_harvest(Collector.Metric.Harvester)
    assert TestHelper.find_metric(metrics, "OtherTransaction/all")
    assert TestHelper.find_metric(metrics, "OtherTransaction/TransactionCategory/MyTaskName")

    assert TestHelper.find_metric(metrics, "External/OtherTransactionTest.External.call/all")
    assert TestHelper.find_metric(metrics, "External/allOther")

    assert TestHelper.find_metric(
             metrics,
             {"External/OtherTransactionTest.External.call",
              "OtherTransaction/TransactionCategory/MyTaskName"}
           )

    span_events = TestHelper.gather_harvest(Collector.SpanEvent.Harvester)
    assert length(span_events) == 3

    TestHelper.pause_harvest_cycle(Collector.TransactionEvent.HarvestCycle)
    TestHelper.pause_harvest_cycle(Collector.TransactionTrace.HarvestCycle)
    TestHelper.pause_harvest_cycle(Collector.Metric.HarvestCycle)
    TestHelper.pause_harvest_cycle(Collector.SpanEvent.HarvestCycle)
  end

  test "Rename an Other transaction" do
    TestHelper.restart_harvest_cycle(Collector.Metric.HarvestCycle)

    Task.async(fn ->
      NewRelic.start_transaction("TransactionCategory", "MyTaskName")

      NewRelic.set_transaction_name("DifferentCategory/DifferentName")

      Process.sleep(15)
    end)
    |> Task.await()

    metrics = TestHelper.gather_harvest(Collector.Metric.Harvester)
    assert TestHelper.find_metric(metrics, "OtherTransaction/DifferentCategory/DifferentName")

    TestHelper.pause_harvest_cycle(Collector.Metric.HarvestCycle)
  end

  test "NewRelic.other_transaction macro" do
    require NewRelic

    TestHelper.restart_harvest_cycle(Collector.Metric.HarvestCycle)

    task =
      Task.async(fn ->
        NewRelic.other_transaction "Category", "ViaMacro" do
          Process.sleep(100)

          :test_value
        end
      end)

    assert :test_value == Task.await(task)

    metrics = TestHelper.gather_harvest(Collector.Metric.Harvester)
    assert TestHelper.find_metric(metrics, "OtherTransaction/Category/ViaMacro")

    TestHelper.pause_harvest_cycle(Collector.Metric.HarvestCycle)
  end

  @tag :capture_log
  test "Error in Other Transaction" do
    TestHelper.restart_harvest_cycle(Collector.TransactionEvent.HarvestCycle)
    TestHelper.restart_harvest_cycle(Collector.ErrorTrace.HarvestCycle)
    TestHelper.restart_harvest_cycle(NewRelic.Harvest.Collector.Metric.HarvestCycle)
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

    [[_, event]] = TestHelper.gather_harvest(Collector.TransactionEvent.Harvester)

    assert event[:error]

    metrics = TestHelper.gather_harvest(Collector.Metric.Harvester)

    assert TestHelper.find_metric(metrics, "Errors/all")
    assert TestHelper.find_metric(metrics, "Errors/allOther")

    TestHelper.pause_harvest_cycle(NewRelic.Harvest.Collector.Metric.HarvestCycle)
    TestHelper.pause_harvest_cycle(Collector.ErrorTrace.HarvestCycle)
    TestHelper.pause_harvest_cycle(Collector.TransactionEvent.HarvestCycle)
  end

  @tag :capture_log
  test "do fail transaction on error exit" do
    reset_config =
      TestHelper.update(:nr_config,
        trace_mode: :infinite
      )

    on_exit(fn ->
      reset_config.()
    end)

    TestHelper.restart_harvest_cycle(TelemetrySdk.Spans.HarvestCycle)
    {:ok, _sup} = Task.Supervisor.start_link(name: TestTaskSup)
    test = self()

    Task.Supervisor.async_nolink(TestTaskSup, fn ->
      NewRelic.start_transaction("Test", "Error")
      send(test, {:sidecar, NewRelic.Transaction.Sidecar.get_sidecar()})
      Process.sleep(10)
      raise RuntimeError
    end)

    assert_receive {:sidecar, sidecar}
    Process.monitor(sidecar)
    assert_receive {:DOWN, _, _, ^sidecar, _}

    [%{spans: spans}] = TestHelper.gather_harvest(TelemetrySdk.Spans.Harvester)

    spansaction =
      Enum.find(spans, fn %{attributes: attr} ->
        attr[:category] == "Transaction" && attr[:name] == "Test/Error"
      end)

    assert spansaction.attributes[:error]
    assert spansaction.attributes[:error_reason] =~ "RuntimeError"
  end

  defmodule ExpectedError do
    defexception message: "Expected!", expected: true
  end

  @tag :capture_log
  test "don't fail transaction on expected error exit" do
    reset_config =
      TestHelper.update(:nr_config,
        trace_mode: :infinite
      )

    on_exit(fn ->
      reset_config.()
    end)

    TestHelper.restart_harvest_cycle(TelemetrySdk.Spans.HarvestCycle)
    {:ok, _sup} = Task.Supervisor.start_link(name: TestTaskSup)
    test = self()

    Task.Supervisor.async_nolink(TestTaskSup, fn ->
      NewRelic.start_transaction("Test", "ExpectedError")
      send(test, {:sidecar, NewRelic.Transaction.Sidecar.get_sidecar()})
      Process.sleep(10)
      raise ExpectedError
    end)

    assert_receive {:sidecar, sidecar}
    Process.monitor(sidecar)
    assert_receive {:DOWN, _, _, ^sidecar, _}

    [%{spans: spans}] = TestHelper.gather_harvest(TelemetrySdk.Spans.Harvester)

    spansaction =
      Enum.find(spans, fn %{attributes: attr} ->
        attr[:category] == "Transaction" && attr[:name] == "Test/ExpectedError"
      end)

    refute spansaction.attributes[:error]
  end
end
