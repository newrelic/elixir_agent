defmodule OtherTransactionTest do
  use ExUnit.Case

  alias NewRelic.Harvest.Collector
  alias NewRelic.Harvest.TelemetrySdk

  setup do
    TestHelper.run_with(:nr_config, license_key: "dummy_key", harvest_enabled: true)
    NewRelic.DistributedTrace.BackoffSampler.reset()

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

    events = TestHelper.gather_harvest(Collector.TransactionEvent.Harvester)
    event = TestHelper.find_event(events, "OtherTransaction/TransactionCategory/MyTaskName")

    assert event[:other] == "transaction"
    assert event[:traceId]
    assert event[:guid]

    assert_in_delta event[:end_time] - event[:start_time], event[:duration_ms], 1

    assert event[:duration_ms] >= 60
    assert event[:total_time_s] >= (60 + 50) / 1000

    [_trace] = TestHelper.gather_harvest(Collector.TransactionTrace.Harvester)

    metrics = TestHelper.gather_harvest(Collector.Metric.Harvester)
    assert TestHelper.find_metric(metrics, "OtherTransaction/all")
    assert TestHelper.find_metric(metrics, "OtherTransaction/TransactionCategory/MyTaskName")

    assert TestHelper.find_metric(metrics, "External/OtherTransactionTest.External.call/all")
    assert TestHelper.find_metric(metrics, "External/allOther")

    assert TestHelper.find_metric(
             metrics,
             {"External/OtherTransactionTest.External.call", "OtherTransaction/TransactionCategory/MyTaskName"}
           )

    span_events = TestHelper.gather_harvest(Collector.SpanEvent.Harvester)
    assert length(span_events) == 4

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
             reason,
             _,
             _,
             _
           ] = trace

    assert name =~ "OtherTransaction"
    assert reason =~ "(RuntimeError) FAIL"

    events = TestHelper.gather_harvest(Collector.TransactionEvent.Harvester)
    event = TestHelper.find_event(events, "OtherTransaction/Task/FailingTask")

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
    TestHelper.run_with(:nr_config, trace_mode: :infinite)

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

    spansaction = TestHelper.find_event(spans, %{"nr.entryPoint": true, name: "Test/Error"})

    assert spansaction.attributes[:error]
    assert spansaction.attributes[:error_reason] =~ "RuntimeError"
  end

  defmodule ExpectedError do
    defexception message: "Expected!", expected: true
  end

  @tag :capture_log
  test "don't fail transaction on expected error exit" do
    TestHelper.run_with(:nr_config, trace_mode: :infinite)

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

    spansaction = TestHelper.find_event(spans, %{"nr.entryPoint": true, name: "Test/ExpectedError"})

    refute spansaction.attributes[:error]
  end

  test "Report a raise that is rescued inside a Transaction" do
    TestHelper.restart_harvest_cycle(Collector.TransactionErrorEvent.HarvestCycle)

    {:ok, pid} =
      Task.start(fn ->
        NewRelic.start_transaction("TestTransaction", "Rescued")

        try do
          raise RuntimeError, "RESCUED"
        rescue
          exception ->
            NewRelic.notice_error(exception, __STACKTRACE__)
            :move_on
        end
      end)

    Process.monitor(pid)
    assert_receive {:DOWN, _ref, :process, ^pid, _reason}, 1_000

    events = TestHelper.gather_harvest(Collector.TransactionErrorEvent.Harvester)

    assert TestHelper.find_event(events, %{"error.message": "(RuntimeError) RESCUED"})
  end
end
