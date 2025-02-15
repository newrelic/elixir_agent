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
    [event | _] = TestHelper.gather_harvest(Collector.TransactionEvent.Harvester)

    assert TestHelper.find_metric(
             metrics,
             "OtherTransaction/Oban/default/ObanExample.Worker/perform",
             1
           )

    assert [
             %{
               :name => "OtherTransaction/Oban/default/ObanExample.Worker/perform",
               :timestamp => timestamp,
               :duration => duration
             },
             %{
               :"oban.worker" => "ObanExample.Worker",
               :"oban.queue" => "default",
               :"oban.job.result" => "success",
               :"oban.job.tags" => "foo,bar"
             }
           ] = event

    assert timestamp |> is_number
    assert duration >= 0.015
    assert duration <= 0.065
  end

  test "instruments a failed job" do
    TestHelper.restart_harvest_cycle(Collector.Metric.HarvestCycle)
    TestHelper.restart_harvest_cycle(Collector.TransactionEvent.HarvestCycle)

    ObanExample.Worker.new(%{error: "error!"}, tags: ["foo", "bar"])
    |> Oban.insert()

    metrics = TestHelper.gather_harvest(Collector.Metric.Harvester)
    [event | _] = TestHelper.gather_harvest(Collector.TransactionEvent.Harvester)

    assert TestHelper.find_metric(
             metrics,
             "OtherTransaction/Oban/default/ObanExample.Worker/perform",
             1
           )

    assert [
             %{:name => "OtherTransaction/Oban/default/ObanExample.Worker/perform"},
             %{
               :error => true,
               :error_kind => :error,
               :"oban.worker" => "ObanExample.Worker",
               :"oban.queue" => "default",
               :"oban.job.result" => "failure",
               :"oban.job.tags" => "foo,bar"
             }
           ] = event
  end
end
