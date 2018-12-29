defmodule TransactionTraceTest do
  use ExUnit.Case
  use Plug.Test

  alias NewRelic.Harvest.Collector
  alias NewRelic.Transaction.Trace

  setup do
    TestHelper.restart_harvest_cycle(Collector.Metric.HarvestCycle)
    TestHelper.restart_harvest_cycle(Collector.TransactionTrace.HarvestCycle)

    on_exit(fn ->
      TestHelper.pause_harvest_cycle(Collector.Metric.HarvestCycle)
      TestHelper.pause_harvest_cycle(Collector.TransactionTrace.HarvestCycle)
    end)
  end

  defmodule HelperModule do
    use NewRelic.Tracer
    @trace :function
    def function(n), do: Process.sleep(n)
  end

  defmodule ExternalService do
    use NewRelic.Tracer
    @trace {:query, category: :external}
    def query(n), do: HelperModule.function(n)
  end

  defmodule TestPlugApp do
    use Plug.Router
    use NewRelic.Transaction

    plug(:match)
    plug(:dispatch)

    get "/transaction_trace" do
      ExternalService.query(101)
      Process.sleep(10)

      t1 =
        Task.async(fn ->
          Task.async(fn ->
            ExternalService.query(202)
            Process.sleep(20)
          end)
          |> Task.await()
        end)

      Process.sleep(50)

      t2 =
        Task.async(fn ->
          ExternalService.query(304)
        end)

      Task.await(t1)
      Task.await(t2)
      ExternalService.query(405)
      send_resp(conn, 200, "transaction_trace")
    end

    get "/supremely_custom_name" do
      NewRelic.set_transaction_name("/supremely/unique/name")
      send_resp(conn, 200, "ok")
    end
  end

  test "Harvester - collect and store some tracez" do
    {:ok, harvester} = Supervisor.start_child(Collector.TransactionTrace.HarvesterSupervisor, [])

    trace1 = %Trace{metric_name: :a, duration: 1, segments: [%Trace.Segment{}]}
    trace2 = %Trace{metric_name: :b, duration: 2, segments: [%Trace.Segment{}]}
    GenServer.cast(harvester, {:report, trace1})
    GenServer.cast(harvester, {:report, trace2})

    traces = GenServer.call(harvester, :gather_harvest)
    assert [t1, _t2] = traces
    assert length(t1) == 10

    # Verify that the Harvester shuts down w/o error
    Process.monitor(harvester)
    Collector.HarvestCycle.send_harvest(Collector.TransactionTrace.HarvesterSupervisor, harvester)
    assert_receive {:DOWN, _ref, _, ^harvester, :shutdown}, 1000
  end

  test "harvest cycle" do
    Application.put_env(:new_relic_agent, :data_report_period, 300)
    TestHelper.restart_harvest_cycle(Collector.TransactionTrace.HarvestCycle)

    first = Collector.HarvestCycle.current_harvester(Collector.TransactionTrace.HarvestCycle)
    Process.monitor(first)

    # Wait until harvest swap
    assert_receive {:DOWN, _ref, _, ^first, :shutdown}, 1000

    second = Collector.HarvestCycle.current_harvester(Collector.TransactionTrace.HarvestCycle)
    Process.monitor(second)

    refute first == second
    assert Process.alive?(second)

    TestHelper.pause_harvest_cycle(Collector.TransactionTrace.HarvestCycle)
    Application.delete_env(:new_relic_agent, :data_report_period)

    # Ensure the last harvester has shut down
    assert_receive {:DOWN, _ref, _, ^second, :shutdown}, 1000
  end

  test "Ignore late reports" do
    TestHelper.restart_harvest_cycle(Collector.TransactionTrace.HarvestCycle)

    harvester =
      Collector.TransactionTrace.HarvestCycle
      |> Collector.HarvestCycle.current_harvester()

    assert :ok == GenServer.call(harvester, :send_harvest)

    GenServer.cast(harvester, {:report, :late_msg})

    assert :completed == GenServer.call(harvester, :send_harvest)

    TestHelper.pause_harvest_cycle(Collector.TransactionTrace.HarvestCycle)
  end

  test "Prepare a payload" do
    TestPlugApp.call(conn(:get, "/supremely_custom_name"), [])

    start_time = 1_440_435_088
    metric_name = "WebTransaction/supremely/unique/name"
    request_url = "http://some.domain/supremely/unique/name"
    duration = 652
    agent_run_id = NewRelic.Harvest.Collector.AgentRun.agent_run_id()

    tx_trace_1 = %Trace{
      start_time: start_time,
      metric_name: metric_name,
      request_url: "#{request_url}/1",
      attributes: %{},
      duration: duration,
      segments: [%Trace.Segment{}]
    }

    tx_trace_2 = %Trace{
      start_time: start_time,
      metric_name: metric_name,
      request_url: "#{request_url}/2",
      attributes: %{},
      duration: duration,
      segments: [%Trace.Segment{}]
    }

    payload = [agent_run_id, Trace.format_traces([tx_trace_1, tx_trace_2])]
    NewRelic.Harvest.Collector.Protocol.transaction_trace(payload)

    [run_id | [[trace_payload_1, _] = trace_payloads]] = payload

    assert run_id == agent_run_id
    assert length(trace_payloads) == 2

    [
      start_time_1,
      duration_1,
      metric_name_1,
      request_url_1,
      _details,
      cat_guid_1,
      reserved_1,
      force_persist_1,
      xray_1,
      synthetics_resource_1
    ] = trace_payload_1

    assert start_time_1 == start_time
    assert duration_1 == duration
    assert metric_name_1 == metric_name
    assert request_url_1 == "#{request_url}/1"
    assert cat_guid_1 == ""
    assert reserved_1 == nil
    assert force_persist_1 == false
    assert xray_1 == nil
    assert synthetics_resource_1 == ""
  end

  test "Transaction Trace instrument & harvest" do
    TestHelper.request(TestPlugApp, conn(:get, "/transaction_trace"))
    TestHelper.request(TestPlugApp, conn(:get, "/transaction_trace"))

    traces = TestHelper.gather_harvest(Collector.TransactionTrace.Harvester)
    assert length(traces) == 2
    Jason.encode!(traces)
  end

  test "Don't report traces with a short duration" do
    longer_duration = 51
    shorter_duration = 49

    refute :ignore ==
             Collector.TransactionTrace.Harvester.report_trace(%Trace{
               duration: longer_duration,
               segments: [%Trace.Segment{}]
             })

    assert :ignore ==
             Collector.TransactionTrace.Harvester.report_trace(%Trace{
               duration: shorter_duration,
               segments: [%Trace.Segment{}]
             })
  end

  test "Store a limited number of slow traces" do
    max_slow_traces = 2
    faster_trace = %{duration: 9}

    not_reached_max_state = %{slowest_traces: []}

    assert %{slowest_traces: [faster_trace]} ==
             Collector.TransactionTrace.Harvester.store_slow_trace(
               not_reached_max_state,
               faster_trace,
               max_slow_traces
             )

    reached_max_state = %{slowest_traces: [%{duration: 10}, %{duration: 9}]}

    assert reached_max_state ==
             Collector.TransactionTrace.Harvester.store_slow_trace(
               reached_max_state,
               faster_trace,
               max_slow_traces
             )
  end

  test "Store new slow traces if they are slower than the slowest" do
    max_slow_traces = 1
    faster_trace = %{duration: 9}
    slower_trace = %{duration: 11}

    starting_state = %{slowest_traces: [%{duration: 10}]}

    assert starting_state ==
             Collector.TransactionTrace.Harvester.store_slow_trace(
               starting_state,
               faster_trace,
               max_slow_traces
             )

    starting_state = %{slowest_traces: [%{duration: 10}]}

    assert %{slowest_traces: [slower_trace]} ==
             Collector.TransactionTrace.Harvester.store_slow_trace(
               starting_state,
               slower_trace,
               max_slow_traces
             )
  end

  test "Store named traces with a limit per bucket" do
    max_named_traces = 2
    trace = %{metric_name: :b}

    not_reached_max_state = %{traces_by_name: %{}}

    assert %{traces_by_name: %{b: [trace]}} ==
             Collector.TransactionTrace.Harvester.store_named_trace(
               not_reached_max_state,
               trace,
               max_named_traces
             )

    reached_max_state = %{traces_by_name: %{b: [%{metric_name: :t1}, %{metric_name: :t2}]}}

    assert reached_max_state ==
             Collector.TransactionTrace.Harvester.store_named_trace(
               reached_max_state,
               trace,
               max_named_traces
             )
  end
end
