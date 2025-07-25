defmodule TransactionErrorEventTest do
  use ExUnit.Case
  use Plug.Test

  alias NewRelic.Harvest
  alias NewRelic.Harvest.Collector
  alias NewRelic.Error.Event

  defmodule SomeGenServer do
    use GenServer

    def start_link(_) do
      GenServer.start_link(__MODULE__, [], name: __MODULE__)
    end

    def init(_) do
      {:ok, %{}}
    end

    def handle_call(:will_fail, _from, _state) do
      raise "GenServer error"
    end
  end

  setup_all do
    start_supervised(SomeGenServer)
    :ok
  end

  defmodule TestPlugApp do
    use Plug.Router

    plug(:match)
    plug(:dispatch)

    get "/error" do
      raise "TransactionError"
      send_resp(conn, 200, "won't happen")
    end

    get "/async_error" do
      Task.async(fn -> Process.sleep(100) end)
      |> Task.await(10)

      send_resp(conn, 200, "won't happen either")
    end

    get "/caught/error" do
      tx = NewRelic.get_transaction()

      Task.Supervisor.async_nolink(TestSup, fn ->
        NewRelic.connect_to_transaction(tx)
        NewRelic.add_attributes(nested: "process")
        raise "NestedTaskError"
      end)

      Process.sleep(50)
      send_resp(conn, 200, "ok, fine")
    end
  end

  test "post required supportability metrics" do
    ts_end = System.system_time(:second)
    ts_start = ts_end - 60
    agent_run_id = NewRelic.Harvest.Collector.AgentRun.agent_run_id()

    data_array = [
      [%{name: "Errors/all", scope: ""}, [42, 0, 0, 0, 0, 0]],
      [%{name: "Supportability/Events/TransactionError/Sent", scope: ""}, [42, 0, 0, 0, 0, 0]],
      [%{name: "Supportability/Events/TransactionError/Seen", scope: ""}, [42, 0, 0, 0, 0, 0]]
    ]

    NewRelic.Harvest.Collector.Protocol.metric_data([agent_run_id, ts_start, ts_end, data_array])
  end

  test "post an error event" do
    agent_run_id = NewRelic.Harvest.Collector.AgentRun.agent_run_id()

    er_1 = %Event{
      error_class: "ErrorClass",
      error_message: "Error: message",
      timestamp: System.system_time(:millisecond) / 1_000,
      transaction_name: "WebTransaction/AgentTest/Transaction/name",
      database_duration: 0.010,
      duration: 0.010,
      agent_attributes: %{
        request_method: "GET",
        http_response_code: 500
      },
      user_attributes: %{
        foo: "bar"
      }
    }

    sampling = %{
      reservoir_size: 100,
      events_seen: 1
    }

    error_events = Event.format_events([er_1])
    payload = [agent_run_id, sampling, error_events]
    NewRelic.Harvest.Collector.Protocol.error_event(payload)
  end

  test "user attributes can be truncated" do
    TestHelper.restart_harvest_cycle(Collector.TransactionErrorEvent.HarvestCycle)

    Collector.TransactionErrorEvent.Harvester.report_error(%Event{
      transaction_name: "Ev1",
      duration: 1,
      user_attributes: %{long_entry: String.duplicate("1", 5000)}
    })

    events = TestHelper.gather_harvest(Collector.TransactionErrorEvent.Harvester)
    event = TestHelper.find_event(events, %{transactionName: "Ev1"})

    assert String.length(event.long_entry) == 4095
  end

  test "collect and store some events" do
    {:ok, harvester} =
      DynamicSupervisor.start_child(
        Collector.TransactionErrorEvent.HarvesterSupervisor,
        Collector.TransactionErrorEvent.Harvester
      )

    ev1 = %Event{transaction_name: "Ev1", duration: 1}
    ev2 = %Event{transaction_name: "Ev2", duration: 2}

    GenServer.cast(harvester, {:report, ev1})
    GenServer.cast(harvester, {:report, ev2})

    events = GenServer.call(harvester, :gather_harvest)
    assert length(events) == 2

    # Verify that the Harvester shuts down w/o error
    Process.monitor(harvester)

    Harvest.HarvestCycle.send_harvest(
      Collector.TransactionErrorEvent.HarvesterSupervisor,
      harvester
    )

    assert_receive {:DOWN, _ref, _, ^harvester, :shutdown}, 1000
  end

  test "harvest cycle" do
    TestHelper.run_with(:application_config, error_event_harvest_cycle: 300)
    TestHelper.restart_harvest_cycle(Collector.TransactionErrorEvent.HarvestCycle)

    first = Harvest.HarvestCycle.current_harvester(Collector.TransactionErrorEvent.HarvestCycle)
    Process.monitor(first)

    # Wait until harvest swap
    assert_receive {:DOWN, _ref, _, ^first, :shutdown}, 1000

    second = Harvest.HarvestCycle.current_harvester(Collector.TransactionErrorEvent.HarvestCycle)

    Process.monitor(second)

    refute first == second
    assert Process.alive?(second)

    # Ensure the last harvester has shut down
    assert_receive {:DOWN, _ref, _, ^second, :shutdown}, 1000
  end

  @tag :capture_log
  test "instrument & harvest" do
    TestHelper.restart_harvest_cycle(Collector.TransactionEvent.HarvestCycle)
    TestHelper.restart_harvest_cycle(Collector.TransactionErrorEvent.HarvestCycle)
    TestHelper.restart_harvest_cycle(Collector.ErrorTrace.HarvestCycle)
    TestHelper.restart_harvest_cycle(Collector.Metric.HarvestCycle)
    Logger.remove_backend(:console)

    TestHelper.request(TestPlugApp, conn(:get, "/error"))

    traces = TestHelper.gather_harvest(Collector.ErrorTrace.Harvester)
    assert length(traces) == 1
    assert NewRelic.JSON.encode!(traces)

    events = TestHelper.gather_harvest(Collector.TransactionErrorEvent.Harvester)
    assert length(events) == 1
    assert NewRelic.JSON.encode!(events)

    metrics = TestHelper.gather_harvest(Collector.Metric.Harvester)
    assert TestHelper.find_metric(metrics, "Errors/all")
    assert TestHelper.find_metric(metrics, "Errors/allWeb")
    assert TestHelper.find_metric(metrics, "Errors/WebTransaction/Plug/GET/error")

    traces = TestHelper.gather_harvest(Collector.TransactionEvent.Harvester)
    assert length(traces) == 1
    assert NewRelic.JSON.encode!(traces)

    Logger.add_backend(:console)
  end

  @tag :capture_log
  test "cowboy request process exit" do
    TestHelper.restart_harvest_cycle(Collector.ErrorTrace.HarvestCycle)
    Logger.remove_backend(:console)

    {:ok, _} = Plug.Cowboy.http(TestPlugApp, [], port: 9999)
    :httpc.request(~c"http://localhost:9999/async_error")

    traces = TestHelper.gather_harvest(Collector.ErrorTrace.Harvester)
    assert Enum.find(traces, &match?([_, _, _, "EXIT", _, _], &1))

    Plug.Cowboy.shutdown(TestPlugApp.HTTP)

    Logger.add_backend(:console)
  end

  test "Ignore late reports" do
    TestHelper.restart_harvest_cycle(Collector.TransactionErrorEvent.HarvestCycle)

    harvester =
      Collector.TransactionErrorEvent.HarvestCycle
      |> Harvest.HarvestCycle.current_harvester()

    assert :ok == GenServer.call(harvester, :send_harvest)

    GenServer.cast(harvester, {:report, :late_msg})

    assert :completed == GenServer.call(harvester, :send_harvest)
  end

  @tag :capture_log
  test "Report a nested error inside the transaction if we catch it" do
    Logger.remove_backend(:console)
    TestHelper.restart_harvest_cycle(Collector.ErrorTrace.HarvestCycle)
    TestHelper.restart_harvest_cycle(Collector.TransactionErrorEvent.HarvestCycle)
    TestHelper.restart_harvest_cycle(Collector.Metric.HarvestCycle)
    TestHelper.restart_harvest_cycle(Collector.TransactionEvent.HarvestCycle)
    {:ok, _sup} = Task.Supervisor.start_link(name: TestSup)

    response = TestHelper.request(TestPlugApp, conn(:get, "/caught/error"))
    assert response.status_code == 200
    assert response.body =~ "ok, fine"

    traces = TestHelper.gather_harvest(Collector.ErrorTrace.Harvester)

    assert length(traces) == 1

    assert [
             [
               _ts,
               "WebTransaction/Plug/GET/caught/error",
               _,
               _,
               %{userAttributes: %{nested: "process"}},
               _
             ]
           ] = traces

    traces = TestHelper.gather_harvest(Collector.TransactionErrorEvent.Harvester)
    assert length(traces) == 1

    events = TestHelper.gather_harvest(Collector.TransactionEvent.Harvester)
    event = TestHelper.find_event(events, "WebTransaction/Plug/GET/caught/error")

    assert event[:error]

    Process.sleep(50)
    Logger.add_backend(:console)
  end

  @tag :capture_log
  test "Report a GenServer call nested exit" do
    TestHelper.restart_harvest_cycle(Collector.ErrorTrace.HarvestCycle)
    TestHelper.restart_harvest_cycle(Collector.TransactionErrorEvent.HarvestCycle)
    TestHelper.restart_harvest_cycle(Collector.Metric.HarvestCycle)
    TestHelper.restart_harvest_cycle(Collector.TransactionEvent.HarvestCycle)
    start_supervised({Task.Supervisor, name: TestSupervisor})

    {:exit, {_exception, _stacktrace}} =
      Task.Supervisor.async_nolink(TestSupervisor, fn ->
        NewRelic.start_transaction("Transaction", "GenServerCall")
        Process.sleep(50)
        GenServer.call(SomeGenServer, :will_fail)
      end)
      |> Task.yield()

    traces = TestHelper.gather_harvest(Collector.TransactionErrorEvent.Harvester)
    trace = TestHelper.find_event(traces, %{transactionName: "OtherTransaction/Transaction/GenServerCall"})
    assert trace[:"error.class"] == "RuntimeError"

    events = TestHelper.gather_harvest(Collector.TransactionEvent.Harvester)
    event = TestHelper.find_event(events, "OtherTransaction/Transaction/GenServerCall")
    assert event[:error]
  end

  defmodule CustomError do
    defexception [:message, :expected]
  end

  @tag :capture_log
  test "record an expected error" do
    TestHelper.restart_harvest_cycle(Collector.ErrorTrace.HarvestCycle)
    TestHelper.restart_harvest_cycle(Collector.Metric.HarvestCycle)
    TestHelper.restart_harvest_cycle(Collector.TransactionErrorEvent.HarvestCycle)
    start_supervised({Task.Supervisor, name: TestSupervisor})

    {:exit, {_exception, _stacktrace}} =
      Task.Supervisor.async_nolink(TestSupervisor, fn ->
        raise __MODULE__.CustomError, message: "FAIL", expected: true
      end)
      |> Task.yield()

    traces = TestHelper.gather_harvest(Collector.TransactionErrorEvent.Harvester)

    assert [
             [
               %{
                 "error.expected": true,
                 "error.message": "(TransactionErrorEventTest.CustomError) FAIL"
               },
               _,
               _
             ]
             | _
           ] = traces
  end
end
