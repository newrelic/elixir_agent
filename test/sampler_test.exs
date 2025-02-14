defmodule SamplerTest do
  use ExUnit.Case, async: false

  alias NewRelic.Harvest.Collector

  defmodule TestProcess do
    use GenServer

    def start_link, do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

    def init(:ok) do
      NewRelic.sample_process()
      {:ok, %{}}
    end

    def handle_call(:work, _from, state) do
      {:reply, fib(10), state}
    end

    def fib(0), do: 0
    def fib(1), do: 1
    def fib(n), do: fib(n - 1) + fib(n - 2)
  end

  test "Beam stats Sampler" do
    TestHelper.restart_harvest_cycle(Collector.CustomEvent.HarvestCycle)
    TestHelper.restart_harvest_cycle(Collector.Metric.HarvestCycle)

    TestHelper.trigger_report(NewRelic.Sampler.Beam)
    events = TestHelper.gather_harvest(Collector.CustomEvent.Harvester)
    metrics = TestHelper.gather_harvest(Collector.Metric.Harvester)

    event = TestHelper.find_event(events, %{category: "BeamStat"})

    assert event[:reductions] > 0
    assert event[:process_count] > 0
    assert event[:scheduler_utilization] > 0.0
    assert event[:scheduler_utilization] < 1.0

    [%{name: "Memory/Physical"}, [_, mb, _, _, _, _]] =
      TestHelper.find_metric(metrics, "Memory/Physical")

    assert 5 < mb
    assert mb < 100

    assert [%{name: "CPU/User Time"}, [_, cpu, _, _, _, _]] =
             TestHelper.find_metric(metrics, "CPU/User Time")

    assert cpu > 0
  end

  test "Process Sampler" do
    TestHelper.restart_harvest_cycle(Collector.CustomEvent.HarvestCycle)
    TestProcess.start_link()

    TestHelper.trigger_report(NewRelic.Sampler.Process)
    events = TestHelper.gather_harvest(Collector.CustomEvent.Harvester)

    assert TestHelper.find_event(events, %{
             category: "ProcessSample",
             name: "SamplerTest.TestProcess",
             message_queue_length: 0
           })
  end

  test "unnamed Process Sampler" do
    TestHelper.restart_harvest_cycle(Collector.CustomEvent.HarvestCycle)

    parent = self()

    spawn(fn ->
      NewRelic.sample_process()
      TestHelper.trigger_report(NewRelic.Sampler.Process)
      send(parent, {:pid, self()})
    end)

    assert_receive {:pid, pid}, 500

    events = TestHelper.gather_harvest(Collector.CustomEvent.Harvester)

    assert TestHelper.find_event(events, %{
             category: "ProcessSample",
             name: inspect(pid),
             message_queue_length: 0
           })
  end

  test "Process Sampler - count work between samplings" do
    TestProcess.start_link()

    TestHelper.restart_harvest_cycle(Collector.CustomEvent.HarvestCycle)
    TestHelper.trigger_report(NewRelic.Sampler.Process)

    events = TestHelper.gather_harvest(Collector.CustomEvent.Harvester)

    %{reductions: first_reductions} =
      TestHelper.find_event(events, %{
        category: "ProcessSample",
        name: "SamplerTest.TestProcess"
      })

    TestHelper.restart_harvest_cycle(Collector.CustomEvent.HarvestCycle)

    GenServer.call(TestProcess, :work)

    TestHelper.trigger_report(NewRelic.Sampler.Process)

    events = TestHelper.gather_harvest(Collector.CustomEvent.Harvester)

    %{reductions: second_reductions} =
      TestHelper.find_event(events, %{
        category: "ProcessSample",
        name: "SamplerTest.TestProcess"
      })

    assert second_reductions > first_reductions
  end

  describe "Sampler.ETS" do
    test "records metrics on ETS tables" do
      TestHelper.restart_harvest_cycle(Collector.CustomEvent.HarvestCycle)

      :ets.new(:test_table, [:named_table])
      for n <- 1..510, do: :ets.insert(:test_table, {n, "BAR"})

      TestHelper.trigger_report(NewRelic.Sampler.Ets)
      events = TestHelper.gather_harvest(Collector.CustomEvent.Harvester)

      assert TestHelper.find_event(events, %{
               category: "EtsStat",
               table_name: ":test_table",
               size: 510
             })
    end

    test "record_sample/1 ignores non-existent tables" do
      assert NewRelic.Sampler.Ets.record_sample(:nope_not_here) == :ignore
    end
  end

  test "detect the processes which are top consumers" do
    top_procs = NewRelic.Sampler.TopProcess.detect_top_processes()

    assert length(top_procs) >= 5
    assert length(top_procs) <= 10
  end

  test "Agent sampler" do
    TestHelper.restart_harvest_cycle(Collector.Metric.HarvestCycle)

    _tx_1 =
      Task.async(fn ->
        NewRelic.start_transaction("Test", "Tx")
        Process.sleep(500)
      end)

    _tx_2 =
      Task.async(fn ->
        NewRelic.start_transaction("Test", "Tx")
        Process.sleep(500)
      end)

    _tx_3 =
      Task.async(fn ->
        NewRelic.start_transaction("Test", "Tx")
        Process.sleep(500)
      end)

    Process.sleep(100)

    TestHelper.trigger_report(NewRelic.Sampler.Agent)

    metrics = TestHelper.gather_harvest(Collector.Metric.Harvester)

    assert [_, [_, active, _, _, _, _]] =
             TestHelper.find_metric(
               metrics,
               "Supportability/ElixirAgent/Sidecar/Process/ActiveCount"
             )

    assert active >= 3

    assert TestHelper.find_metric(
             metrics,
             "Supportability/ElixirAgent/Sidecar/Stores/LookupStore/Size"
           )

    assert TestHelper.find_metric(
             metrics,
             "Supportability/ElixirAgent/Sidecar/Stores/ContextStore/Size"
           )
  end
end
