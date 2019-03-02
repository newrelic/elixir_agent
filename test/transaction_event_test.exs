defmodule TransactionEventTest do
  use ExUnit.Case
  use Plug.Test

  alias NewRelic.Harvest.Collector
  alias NewRelic.Transaction.Event

  defmodule TestPlugApp do
    use Plug.Router
    use NewRelic.Transaction

    plug(:match)
    plug(:dispatch)

    get "/" do
      Process.sleep(10)
      send_resp(conn, 200, "transactionEvent")
    end
  end

  test "post a transaction event" do
    agent_run_id = Collector.AgentRun.agent_run_id()

    tr_1 = %Event{
      web_duration: 0.010,
      database_duration: nil,
      timestamp: System.system_time(:millisecond) / 1_000,
      name: "WebTransaction/AgentTest/Transaction/name",
      duration: 0.010,
      type: "Transaction",
      user_attributes: %{
        foo: "bar"
      }
    }

    sampling = %{
      reservoir_size: 100,
      events_seen: 1
    }

    transaction_events = Event.format_events([tr_1])
    payload = [agent_run_id, sampling, transaction_events]
    Collector.Protocol.transaction_event(payload)
  end

  test "collect and store top priority events" do
    Application.put_env(:new_relic_agent, :transaction_event_reservoir_size, 2)
    {:ok, harvester} = Supervisor.start_child(Collector.TransactionEvent.HarvesterSupervisor, [])

    ev1 = %Event{name: "Ev1", duration: 1, user_attributes: %{priority: 3}}
    ev2 = %Event{name: "Ev2", duration: 2, user_attributes: %{priority: 2}}
    ev3 = %Event{name: "Ev3", duration: 3, user_attributes: %{priority: 1}}

    GenServer.cast(harvester, {:report, ev1})
    GenServer.cast(harvester, {:report, ev2})
    GenServer.cast(harvester, {:report, ev3})

    events = GenServer.call(harvester, :gather_harvest)
    assert length(events) == 2

    assert Enum.find(events, fn [_, tx] -> tx.priority == 3 end)
    assert Enum.find(events, fn [_, tx] -> tx.priority == 2 end)
    refute Enum.find(events, fn [_, tx] -> tx.priority == 1 end)

    # Verify that the Harvester shuts down w/o error
    Process.monitor(harvester)
    Collector.HarvestCycle.send_harvest(Collector.TransactionEvent.HarvesterSupervisor, harvester)
    assert_receive {:DOWN, _ref, _, ^harvester, :shutdown}, 1000

    Application.delete_env(:new_relic_agent, :transaction_event_reservoir_size)
  end

  test "user attributes can be truncated" do
    TestHelper.restart_harvest_cycle(Collector.TransactionEvent.HarvestCycle)

    Collector.TransactionEvent.Harvester.report_event(%Event{
      name: "Ev1",
      duration: 1,
      user_attributes: %{long_entry: String.duplicate("1", 5000)}
    })

    [[_, attrs]] = TestHelper.gather_harvest(Collector.TransactionEvent.Harvester)

    assert String.length(attrs.long_entry) == 4095

    TestHelper.pause_harvest_cycle(Collector.TransactionEvent.HarvestCycle)
  end

  test "harvest cycle" do
    Application.put_env(:new_relic_agent, :transaction_event_harvest_cycle, 300)
    TestHelper.restart_harvest_cycle(Collector.TransactionEvent.HarvestCycle)

    first = Collector.HarvestCycle.current_harvester(Collector.TransactionEvent.HarvestCycle)
    Process.monitor(first)

    # Wait until harvest swap
    assert_receive {:DOWN, _ref, _, ^first, :shutdown}, 1000

    second = Collector.HarvestCycle.current_harvester(Collector.TransactionEvent.HarvestCycle)
    Process.monitor(second)

    refute first == second
    assert Process.alive?(second)

    TestHelper.pause_harvest_cycle(Collector.TransactionEvent.HarvestCycle)
    Application.delete_env(:new_relic_agent, :transaction_event_harvest_cycle)

    # Ensure the last harvester has shut down
    assert_receive {:DOWN, _ref, _, ^second, :shutdown}, 1000
  end

  test "instrument & harvest" do
    TestHelper.restart_harvest_cycle(Collector.TransactionEvent.HarvestCycle)

    TestPlugApp.call(conn(:get, "/"), [])
    TestPlugApp.call(conn(:get, "/"), [])

    [event | _] = events = TestHelper.gather_harvest(Collector.TransactionEvent.Harvester)

    assert length(events) == 2
    assert [%{name: "WebTransaction/Plug/GET"}, _] = event

    TestHelper.pause_harvest_cycle(Collector.TransactionEvent.HarvestCycle)
  end

  test "Ignore late reports" do
    TestHelper.restart_harvest_cycle(Collector.TransactionEvent.HarvestCycle)

    harvester =
      Collector.TransactionEvent.HarvestCycle
      |> Collector.HarvestCycle.current_harvester()

    assert :ok == GenServer.call(harvester, :send_harvest)

    GenServer.cast(harvester, {:report, :late_msg})

    assert :completed == GenServer.call(harvester, :send_harvest)

    TestHelper.pause_harvest_cycle(Collector.TransactionEvent.HarvestCycle)
  end

  test "Respect the reservoir_size" do
    Application.put_env(:new_relic_agent, :transaction_event_reservoir_size, 3)
    TestHelper.restart_harvest_cycle(Collector.TransactionEvent.HarvestCycle)

    Task.async(fn ->
      TestPlugApp.call(conn(:get, "/"), [])
      TestPlugApp.call(conn(:get, "/"), [])
      TestPlugApp.call(conn(:get, "/"), [])
      TestPlugApp.call(conn(:get, "/"), [])
      TestPlugApp.call(conn(:get, "/"), [])
    end)
    |> Task.await()

    events = TestHelper.gather_harvest(Collector.TransactionEvent.Harvester)
    assert length(events) == 3

    Application.delete_env(:new_relic_agent, :transaction_event_reservoir_size)
    TestHelper.pause_harvest_cycle(Collector.TransactionEvent.HarvestCycle)
  end
end
