defmodule ObanExampleTest do
  use ExUnit.Case

  alias NewRelic.Harvest.Collector

  setup_all context, do: TestSupport.simulate_agent_enabled(context)
  setup_all context, do: TestSupport.simulate_agent_run(context)

  test "instruments a job" do
    TestSupport.restart_harvest_cycle(Collector.Metric.HarvestCycle)
    TestSupport.restart_harvest_cycle(Collector.TransactionEvent.HarvestCycle)

    ObanExample.Worker.new(%{some: "args"}, tags: ["foo", "bar"])
    |> Oban.insert()

    metrics = TestSupport.gather_harvest(Collector.Metric.Harvester)
    [event | _] = TestSupport.gather_harvest(Collector.TransactionEvent.Harvester)

    assert TestSupport.find_metric(
             metrics,
             "OtherTransaction/Oban/ObanExample.Worker/perform",
             1
           )

    assert [
             %{:name => "OtherTransaction/Oban/ObanExample.Worker/perform"},
             %{
               :"oban.job.worker" => "ObanExample.Worker",
               :"oban.job.queue" => "default",
               :"oban.job.tags" => "foo,bar"
             }
           ] = event
  end
end
