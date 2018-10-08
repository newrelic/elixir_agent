defmodule SamplerTest do
  use ExUnit.Case

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

    TestProcess.fib(15)

    TestHelper.trigger_report(NewRelic.Sampler.Beam)
    events = TestHelper.gather_harvest(Collector.CustomEvent.Harvester)
    metrics = TestHelper.gather_harvest(Collector.Metric.Harvester)

    assert Enum.find(events, fn [_, event, _] ->
             event[:category] == :BeamStat && event[:reductions] > 0 && event[:process_count] > 0
           end)

    [%{name: "Memory/Physical"}, [_, mb, _, _, _, _]] =
      TestHelper.find_metric(metrics, "Memory/Physical")

    assert 5 < mb
    assert mb < 100

    assert [%{name: "CPU/User Time"}, [_, cpu, _, _, _, _]] =
             TestHelper.find_metric(metrics, "CPU/User Time")

    assert cpu > 0
  end

  test "Calculate scheduler utilization" do
    last = :erlang.statistics(:scheduler_wall_time)

    TestProcess.fib(20)
    current = :erlang.statistics(:scheduler_wall_time)

    util_1 = NewRelic.Sampler.Beam.scheduler_utilization_delta(current, last)
    assert util_1 > 0.05

    Process.sleep(5)
    next = :erlang.statistics(:scheduler_wall_time)
    util_2 = NewRelic.Sampler.Beam.scheduler_utilization_delta(next, last)
    assert util_1 > util_2
  end

  test "Process Sampler" do
    TestHelper.restart_harvest_cycle(Collector.CustomEvent.HarvestCycle)
    TestProcess.start_link()

    TestHelper.trigger_report(NewRelic.Sampler.Process)
    events = TestHelper.gather_harvest(Collector.CustomEvent.Harvester)

    assert Enum.find(events, fn [_, event, _] ->
             event[:category] == :ProcessSample && event[:name] == "SamplerTest.TestProcess" &&
               event[:message_queue_length] == 0
           end)
  end

  test "unnamed Process Sampler" do
    TestHelper.restart_harvest_cycle(Collector.CustomEvent.HarvestCycle)

    parent = self()

    spawn(fn ->
      NewRelic.sample_process()
      TestHelper.trigger_report(NewRelic.Sampler.Process)
      send(parent, :continue)
    end)

    assert_receive :continue, 500

    events = TestHelper.gather_harvest(Collector.CustomEvent.Harvester)

    assert Enum.find(events, fn [_, event, _] ->
             event[:category] == :ProcessSample && event[:name] =~ "PID" &&
               event[:message_queue_length] == 0
           end)
  end

  test "Process Sampler - count work between samplings" do
    TestProcess.start_link()

    TestHelper.restart_harvest_cycle(Collector.CustomEvent.HarvestCycle)
    TestHelper.trigger_report(NewRelic.Sampler.Process)

    events = TestHelper.gather_harvest(Collector.CustomEvent.Harvester)

    [_, %{reductions: first_reductions}, _] =
      Enum.find(events, fn [_, event, _] ->
        event[:category] == :ProcessSample && event[:name] == "SamplerTest.TestProcess"
      end)

    TestHelper.restart_harvest_cycle(Collector.CustomEvent.HarvestCycle)

    GenServer.call(TestProcess, :work)

    TestHelper.trigger_report(NewRelic.Sampler.Process)

    events = TestHelper.gather_harvest(Collector.CustomEvent.Harvester)

    [_, %{reductions: second_reductions}, _] =
      Enum.find(events, fn [_, event, _] ->
        event[:category] == :ProcessSample && event[:name] == "SamplerTest.TestProcess"
      end)

    assert second_reductions > first_reductions
  end

  describe "Sampler.ETS" do
    test "records metrics on ETS tables" do
      TestHelper.restart_harvest_cycle(Collector.CustomEvent.HarvestCycle)

      :ets.new(:test_table, [:named_table])
      for n <- 1..510, do: :ets.insert(:test_table, {n, "BAR"})

      TestHelper.trigger_report(NewRelic.Sampler.Ets)
      events = TestHelper.gather_harvest(Collector.CustomEvent.Harvester)

      assert Enum.find(events, fn [_, event, _] ->
               event[:category] == :EtsStat && event[:table_name] == ":test_table" &&
                 event[:size] == 510
             end)
    end

    test "record_sample/1 ignores non-existent tables" do
      assert NewRelic.Sampler.Ets.record_sample(:nope_not_here) == :ignore
    end
  end
end
