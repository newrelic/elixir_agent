defmodule QuantumExampleTest do
  use ExUnit.Case

  import Crontab.CronExpression

  alias NewRelic.Harvest.Collector

  setup_all context, do: TestSupport.simulate_agent_enabled(context)

  @tag :capture_log
  test "Quantum metrics" do
    TestSupport.restart_harvest_cycle(Collector.Metric.HarvestCycle)
    TestSupport.restart_harvest_cycle(Collector.TransactionEvent.HarvestCycle)

    run_job!(:example, fn -> :ok end)

    metrics = TestSupport.gather_harvest(Collector.Metric.Harvester)

    assert TestSupport.find_metric(
             metrics,
             "OtherTransaction/Quantum/QuantumExample.Scheduler/example"
           )

    [[_, event]] = TestSupport.gather_harvest(Collector.TransactionEvent.Harvester)

    assert event[:"quantum.scheduler"] == "QuantumExample.Scheduler"
    assert event[:"quantum.job_name"] == "example"
    assert event[:"quantum.job_schedule"] == "~e[1 * * * * *]"
    assert event[:"quantum.job_timezone"] == "utc"
  end

  @tag :capture_log
  test "Quantum error" do
    TestSupport.restart_harvest_cycle(Collector.Metric.HarvestCycle)
    TestSupport.restart_harvest_cycle(Collector.TransactionEvent.HarvestCycle)

    run_job!(:example_with_error, fn -> raise "BREAK" end)

    metrics = TestSupport.gather_harvest(Collector.Metric.Harvester)

    assert TestSupport.find_metric(
             metrics,
             "OtherTransaction/Quantum/QuantumExample.Scheduler/example_with_error"
           )

    [[_, event]] = TestSupport.gather_harvest(Collector.TransactionEvent.Harvester)

    assert event[:"quantum.scheduler"] == "QuantumExample.Scheduler"
    assert event[:"quantum.job_name"] == "example_with_error"
    assert event[:"quantum.job_schedule"] == "~e[1 * * * * *]"
    assert event[:"quantum.job_timezone"] == "utc"
    assert event[:error]
  end

  defp run_job!(name, task) do
    :ok =
      QuantumExample.Scheduler.new_job()
      |> Quantum.Job.set_name(name)
      |> Quantum.Job.set_task(task)
      |> Quantum.Job.set_schedule(~e[1 * * * *])
      |> QuantumExample.Scheduler.add_job()

    :ok = QuantumExample.Scheduler.run_job(name)

    on_exit(fn ->
      :ok = QuantumExample.Scheduler.delete_job(name)
    end)
  end
end
