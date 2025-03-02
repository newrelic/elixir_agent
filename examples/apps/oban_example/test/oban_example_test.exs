defmodule ObanExampleTest do
  use ExUnit.Case

  alias NewRelic.Harvest.Collector

  setup_all do
    TestHelper.simulate_agent_enabled()
    TestHelper.simulate_agent_run()
  end

  test "instruments a job" do
    TestHelper.restart_harvest_cycle(Collector.Metric.HarvestCycle)
    TestHelper.restart_harvest_cycle(Collector.TransactionEvent.HarvestCycle)

    ObanExample.Worker.new(%{some: "args"}, tags: ["foo", "bar"])
    |> Oban.insert()

    metrics = TestHelper.gather_harvest(Collector.Metric.Harvester)
    events = TestHelper.gather_harvest(Collector.TransactionEvent.Harvester)

    assert TestHelper.find_metric(
             metrics,
             "OtherTransaction/Oban/default/ObanExample.Worker/perform",
             1
           )

    event =
      TestHelper.find_event(events, "OtherTransaction/Oban/default/ObanExample.Worker/perform")

    assert event[:timestamp] |> is_number
    assert event[:duration] >= 0.015
    assert event[:duration] <= 0.065
    assert event[:duration] <= 0.065
    assert event[:"oban.worker"] == "ObanExample.Worker"
    assert event[:"oban.queue"] == "default"
    assert event[:"oban.job.result"] == "success"
    assert event[:"oban.job.tags"] == "foo,bar"
  end

  test "instruments a failed job" do
    TestHelper.restart_harvest_cycle(Collector.Metric.HarvestCycle)
    TestHelper.restart_harvest_cycle(Collector.TransactionEvent.HarvestCycle)

    ObanExample.Worker.new(%{error: "error!"}, tags: ["foo", "bar"])
    |> Oban.insert()

    metrics = TestHelper.gather_harvest(Collector.Metric.Harvester)
    events = TestHelper.gather_harvest(Collector.TransactionEvent.Harvester)

    assert TestHelper.find_metric(
             metrics,
             "OtherTransaction/Oban/default/ObanExample.Worker/perform",
             1
           )

    event =
      TestHelper.find_event(events, "OtherTransaction/Oban/default/ObanExample.Worker/perform")

    assert event[:timestamp] |> is_number
    assert event[:error] == true
    assert event[:error_kind] == :error
    assert event[:"oban.worker"] == "ObanExample.Worker"
    assert event[:"oban.queue"] == "default"
    assert event[:"oban.job.result"] == "failure"
    assert event[:"oban.job.tags"] == "foo,bar"
  end
end
