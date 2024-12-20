defmodule ErrorTraceTest do
  use ExUnit.Case

  alias NewRelic.Error.Trace
  alias NewRelic.Harvest
  alias NewRelic.Harvest.Collector

  test "post an error trace" do
    agent_run_id = Collector.AgentRun.agent_run_id()

    er_1 = %Trace{
      timestamp: System.system_time(:millisecond) / 1_000,
      transaction_name: "WebTransaction/AgentTest/Transaction/name",
      message: "Error: message",
      error_type: "ErrorClass",
      stack_trace: ["line1", "line2", "line3"],
      agent_attributes: %{
        request_uri: "http://google.com"
      },
      user_attributes: %{
        foo: "bar"
      }
    }

    errors = Trace.format_errors([er_1])
    payload = [agent_run_id, errors]
    Collector.Protocol.error(payload)
  end

  test "collect and store some error traces" do
    {:ok, harvester} =
      DynamicSupervisor.start_child(
        Collector.ErrorTrace.HarvesterSupervisor,
        Collector.ErrorTrace.Harvester
      )

    tr1 = %Trace{error_type: "Err1"}
    tr2 = %Trace{error_type: "Err2"}

    GenServer.cast(harvester, {:report, tr1})
    GenServer.cast(harvester, {:report, tr2})

    traces = GenServer.call(harvester, :gather_harvest)
    assert length(traces) == 2

    for n <- 1..30, do: GenServer.cast(harvester, {:report, %Trace{error_type: n}})
    traces = GenServer.call(harvester, :gather_harvest)
    assert length(traces) == 20

    # Verify that the Harvester shuts down w/o error
    Process.monitor(harvester)
    Harvest.HarvestCycle.send_harvest(Collector.ErrorTrace.HarvesterSupervisor, harvester)
    assert_receive {:DOWN, _ref, _, ^harvester, :shutdown}, 1000
  end

  test "harvest cycle" do
    Application.put_env(:new_relic_agent, :data_report_period, 300)
    TestHelper.restart_harvest_cycle(Collector.ErrorTrace.HarvestCycle)

    first = Harvest.HarvestCycle.current_harvester(Collector.ErrorTrace.HarvestCycle)
    Process.monitor(first)

    # Wait until harvest swap
    assert_receive {:DOWN, _ref, _, ^first, :shutdown}, 1000

    second = Harvest.HarvestCycle.current_harvester(Collector.ErrorTrace.HarvestCycle)
    Process.monitor(second)

    refute first == second
    assert Process.alive?(second)

    TestHelper.pause_harvest_cycle(Collector.ErrorTrace.HarvestCycle)
    Application.delete_env(:new_relic_agent, :data_report_period)

    # Ensure the last harvester has shut down
    assert_receive {:DOWN, _ref, _, ^second, :shutdown}, 1000
  end

  test "instrument & harvest" do
    TestHelper.restart_harvest_cycle(Collector.ErrorTrace.HarvestCycle)

    :proc_lib.spawn(fn -> raise "RAISE" end)

    traces = TestHelper.gather_harvest(Collector.ErrorTrace.Harvester)
    refute Enum.empty?(traces)

    TestHelper.pause_harvest_cycle(Collector.ErrorTrace.HarvestCycle)
  end

  test "Ignore late reports" do
    TestHelper.restart_harvest_cycle(Collector.ErrorTrace.HarvestCycle)

    harvester =
      Collector.ErrorTrace.HarvestCycle
      |> Harvest.HarvestCycle.current_harvester()

    assert :ok == GenServer.call(harvester, :send_harvest)

    GenServer.cast(harvester, {:report, :late_msg})

    assert :completed == GenServer.call(harvester, :send_harvest)

    TestHelper.pause_harvest_cycle(Collector.ErrorTrace.HarvestCycle)
  end

  defmodule CustomError do
    defexception [:message, :expected]
  end

  @tag :capture_log
  test "record an expected error" do
    TestHelper.restart_harvest_cycle(Collector.ErrorTrace.HarvestCycle)
    start_supervised({Task.Supervisor, name: TestSupervisor})

    {:exit, {_exception, _stacktrace}} =
      Task.Supervisor.async_nolink(TestSupervisor, fn ->
        raise __MODULE__.CustomError, message: "FAIL", expected: true
      end)
      |> Task.yield()

    traces = TestHelper.gather_harvest(Collector.ErrorTrace.Harvester)

    assert [
             [
               _ts,
               _,
               "(ErrorTraceTest.CustomError) FAIL",
               _,
               %{
                 intrinsics: %{
                   "error.expected": true
                 }
               },
               _
             ]
             | _
           ] = traces

    TestHelper.pause_harvest_cycle(Collector.ErrorTrace.HarvestCycle)
  end

  test "Doesn't report an error if the handler is not installed" do
    TestHelper.restart_harvest_cycle(Collector.ErrorTrace.HarvestCycle)
    NewRelic.Error.Supervisor.remove_filter()

    :proc_lib.spawn(fn ->
      raise "RAISE"
    end)

    :timer.sleep(100)

    traces = TestHelper.gather_harvest(Collector.ErrorTrace.Harvester)
    assert length(traces) == 0

    NewRelic.Error.Supervisor.add_filter()

    :proc_lib.spawn(fn ->
      raise "RAISE"
    end)

    :timer.sleep(100)

    traces = TestHelper.gather_harvest(Collector.ErrorTrace.Harvester)
    assert length(traces) == 1
  end
end
