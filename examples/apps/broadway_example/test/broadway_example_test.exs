defmodule BroadwayExampleTest do
  use ExUnit.Case

  alias NewRelic.Harvest.Collector

  setup_all do
    # Simulate the agent fully starting up
    Process.whereis(Collector.TaskSupervisor) ||
      NewRelic.EnabledSupervisor.start_link(:ok)

    :ok
  end

  test "Broadway Processor metrics generated" do
    TestHelper.restart_harvest_cycle(Collector.Metric.HarvestCycle)

    ref = Broadway.test_messages(BroadwayExample.Broadway, [1, 2, 3])
    assert_receive {:ack, ^ref, successful, failed}, :timer.seconds(3)
    assert length(successful) == 3
    assert length(failed) == 0

    metrics = TestHelper.gather_harvest(Collector.Metric.Harvester)

    assert TestHelper.find_metric(
             metrics,
             "OtherTransaction/Broadway/BroadwayExample.Broadway/Processor/example_processor_key",
             3
           )

    assert TestHelper.find_metric(
             metrics,
             "OtherTransaction/Broadway/BroadwayExample.Broadway/Consumer/example_batcher_key",
             1
           )
  end
end
