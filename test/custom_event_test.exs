defmodule CustomEventTest do
  use ExUnit.Case

  alias NewRelic.Harvest
  alias NewRelic.Harvest.Collector
  alias NewRelic.Custom.Event

  test "post a custom event" do
    agent_run_id = Collector.AgentRun.agent_run_id()

    tr_1 = %Event{
      timestamp: System.system_time(:millisecond) / 1_000,
      type: "CustomEventTest",
      attributes: %{
        foo: "bar"
      }
    }

    sampling = %{
      reservoir_size: 100,
      events_seen: 1
    }

    custom_events = Event.format_events([tr_1])
    payload = [agent_run_id, sampling, custom_events]
    Collector.Protocol.custom_event(payload)
  end

  test "collect and store some events" do
    {:ok, harvester} =
      DynamicSupervisor.start_child(
        Collector.CustomEvent.HarvesterSupervisor,
        Collector.CustomEvent.Harvester
      )

    ev1 = %Event{
      type: "CustomEventTest",
      timestamp: System.system_time(:millisecond) / 1_000,
      attributes: %{foo: "baz"}
    }

    ev2 = %Event{
      type: "CustomEventTest",
      timestamp: System.system_time(:millisecond) / 1_000,
      attributes: %{foo: "bar"}
    }

    GenServer.cast(harvester, {:report, ev1})
    GenServer.cast(harvester, {:report, ev2})

    events = GenServer.call(harvester, :gather_harvest)
    assert length(events) == 2

    # Verify that the Harvester shuts down w/o error
    Process.monitor(harvester)
    Harvest.HarvestCycle.send_harvest(Collector.CustomEvent.HarvesterSupervisor, harvester)
    assert_receive {:DOWN, _ref, _, ^harvester, :shutdown}, 1000
  end

  test "user attributes can be truncated" do
    TestHelper.restart_harvest_cycle(Collector.CustomEvent.HarvestCycle)

    NewRelic.report_custom_event("CustomEventTest", %{name: "long", long_entry: String.duplicate("1", 5000)})

    events = TestHelper.gather_harvest(Collector.CustomEvent.Harvester)
    event = TestHelper.find_event(events, "long")
    assert String.length(event.long_entry) == 4095
  end

  test "harvest cycle" do
    TestHelper.run_with(:application_config, custom_event_harvest_cycle: 300)
    TestHelper.restart_harvest_cycle(Collector.CustomEvent.HarvestCycle)

    first = Harvest.HarvestCycle.current_harvester(Collector.CustomEvent.HarvestCycle)
    Process.monitor(first)

    # Wait until harvest swap
    assert_receive {:DOWN, _ref, _, ^first, :shutdown}, 1000

    second = Harvest.HarvestCycle.current_harvester(Collector.CustomEvent.HarvestCycle)
    Process.monitor(second)

    refute first == second
    assert Process.alive?(second)

    # Ensure the last harvester has shut down
    assert_receive {:DOWN, _ref, _, ^second, :shutdown}, 1000
  end

  test "instrument & harvest" do
    TestHelper.restart_harvest_cycle(Collector.CustomEvent.HarvestCycle)

    NewRelic.report_custom_event("CustomEventTest", %{foo: "bar"})
    NewRelic.report_custom_event("CustomEventTest", %{foo: "baz"})

    events = TestHelper.gather_harvest(Collector.CustomEvent.Harvester)
    assert length(events) == 2
  end

  test "post supportability metrics" do
    TestHelper.restart_harvest_cycle(Collector.CustomEvent.HarvestCycle)
    TestHelper.restart_harvest_cycle(Collector.Metric.HarvestCycle)

    NewRelic.report_custom_event("CustomEventTest", %{foo: "bar"})
    NewRelic.report_custom_event("CustomEventTest", %{foo: "baz"})

    Collector.CustomEvent.HarvestCycle
    |> NewRelic.Harvest.HarvestCycle.current_harvester()
    |> GenServer.call(:send_harvest)

    metrics = TestHelper.gather_harvest(Collector.Metric.Harvester)

    assert TestHelper.find_metric(
             metrics,
             "Supportability/Elixir/Collector/HarvestSeen/CustomEventData"
           )

    assert TestHelper.find_metric(
             metrics,
             "Supportability/Elixir/Collector/HarvestSize/CustomEventData"
           )
  end

  test "Handle non-serializable attribute values" do
    TestHelper.restart_harvest_cycle(Collector.CustomEvent.HarvestCycle)

    NewRelic.report_custom_event("CustomEventTest", %{
      good_value: "A string",
      bad_value: {:error, :timeout}
    })

    events = TestHelper.gather_harvest(Collector.CustomEvent.Harvester)
    NewRelic.JSON.encode!(events)

    assert TestHelper.find_event(events, %{good_value: "A string", bad_value: "[BAD_VALUE]"})
  end

  test "Ignore late reports" do
    TestHelper.restart_harvest_cycle(Collector.CustomEvent.HarvestCycle)

    harvester =
      Collector.CustomEvent.HarvestCycle
      |> Harvest.HarvestCycle.current_harvester()

    assert :ok == GenServer.call(harvester, :send_harvest)

    GenServer.cast(harvester, {:report, :late_msg})

    assert :completed == GenServer.call(harvester, :send_harvest)
  end

  test "Annotate events with user's configured attributes" do
    TestHelper.restart_harvest_cycle(Collector.CustomEvent.HarvestCycle)
    NewRelic.report_custom_event(:Event, %{key: "TestEvent"})

    events = TestHelper.gather_harvest(Collector.CustomEvent.Harvester)

    assert TestHelper.find_event(events, %{key: "TestEvent", test_attribute: "test_value"})
  end

  test "Respect the reservoir_size" do
    TestHelper.run_with(:application_config, custom_event_reservoir_size: 3)
    TestHelper.restart_harvest_cycle(Collector.CustomEvent.HarvestCycle)

    NewRelic.report_custom_event(:Event, %{key: "TestEvent1"})
    NewRelic.report_custom_event(:Event, %{key: "TestEvent2"})
    NewRelic.report_custom_event(:Event, %{key: "TestEvent3"})
    NewRelic.report_custom_event(:Event, %{key: "TestEvent4"})
    NewRelic.report_custom_event(:Event, %{key: "TestEvent5"})

    events = TestHelper.gather_harvest(Collector.CustomEvent.Harvester)
    assert length(events) == 3
  end
end
