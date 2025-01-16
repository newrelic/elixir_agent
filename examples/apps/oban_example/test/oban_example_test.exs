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
  end

  test "instruments a failed job" do
    TestSupport.restart_harvest_cycle(Collector.Metric.HarvestCycle)
    TestSupport.restart_harvest_cycle(Collector.TransactionEvent.HarvestCycle)

    ObanExample.Worker.new(%{error: "error!"}, tags: ["foo", "bar"])
    |> Oban.insert()

    metrics = TestSupport.gather_harvest(Collector.Metric.Harvester)
    [event | _] = TestSupport.gather_harvest(Collector.TransactionEvent.Harvester)

    assert TestSupport.find_metric(
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
