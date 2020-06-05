defmodule TracerTest do
  use ExUnit.Case

  alias NewRelic.Harvest.Collector

  defmodule Traced do
    use NewRelic.Tracer

    @trace :fun
    def fun do
    end

    @trace :funny
    def funny do
    end

    @trace :bar
    def foo do
    end

    @trace {:query, category: :external}
    def query do
    end

    @trace {:db_query, category: :datastore}
    def db_query do
      :result
    end

    @trace :default
    def default(arg \\ 3), do: arg

    @trace :guard
    def guard(arg) when is_atom(arg), do: arg

    @trace :multiple_function_heads
    def multi(1, arg2), do: {10, arg2}
    def multi(2, arg2), do: {20, arg2}
    def multi(arg1, arg2), do: {arg1, arg2}

    def call_priv(), do: priv()
    @trace :priv
    defp priv(), do: :priv

    @trace :ignored
    def ignored(:left = _ignored), do: :left
    def ignored(_ignored = :right), do: :right
    def ignored(_ignored), do: :ignored

    @trace :naive
    def naive(%NaiveDateTime{}), do: :naive

    @trace :error
    def error(exception) do
      raise exception
    end

    @trace :default_multiclause
    def default_multiclause(value \\ :default_val)
    def default_multiclause(:case_1), do: :case_1_return
    def default_multiclause(value), do: value

    defstruct [:key]

    @trace :mod
    def mod(%__MODULE__{key: val}), do: val

    @trace :rescuer
    def rescuer() do
      :do_something
    rescue
      error -> error
    end
  end

  test "function that has error" do
    TestHelper.restart_harvest_cycle(Collector.CustomEvent.HarvestCycle)

    assert_raise(RuntimeError, fn ->
      Traced.error(RuntimeError)
    end)

    TestHelper.trigger_report(NewRelic.Aggregate.Reporter)
    events = TestHelper.gather_harvest(Collector.CustomEvent.Harvester)

    assert Enum.find(events, fn [_, event, _] ->
             event[:category] == :Metric && event[:mfa] == "TracerTest.Traced.error/1" &&
               event[:call_count] == 1
           end)
  end

  test "function with function head" do
    TestHelper.restart_harvest_cycle(Collector.CustomEvent.HarvestCycle)

    assert :default_val == Traced.default_multiclause()
    assert :case_1_return == Traced.default_multiclause(:case_1)
    assert :regular_call == Traced.default_multiclause(:regular_call)

    TestHelper.trigger_report(NewRelic.Aggregate.Reporter)
    events = TestHelper.gather_harvest(Collector.CustomEvent.Harvester)

    assert Enum.find(events, fn [_, event, _] ->
             event[:category] == :Metric &&
               event[:mfa] == "TracerTest.Traced.default_multiclause/1" && event[:call_count] == 3
           end)
  end

  test "Basic traced function" do
    TestHelper.restart_harvest_cycle(Collector.CustomEvent.HarvestCycle)

    Traced.fun()

    TestHelper.trigger_report(NewRelic.Aggregate.Reporter)
    events = TestHelper.gather_harvest(Collector.CustomEvent.Harvester)

    assert Enum.find(events, fn [_, event, _] ->
             event[:category] == :Metric && event[:mfa] == "TracerTest.Traced.fun/0" &&
               event[:call_count] == 1
           end)
  end

  test "Trace function with additional name" do
    TestHelper.restart_harvest_cycle(Collector.CustomEvent.HarvestCycle)

    Traced.foo()

    TestHelper.trigger_report(NewRelic.Aggregate.Reporter)
    events = TestHelper.gather_harvest(Collector.CustomEvent.Harvester)

    assert Enum.find(events, fn [_, event, _] ->
             event[:category] == :Metric && event[:mfa] == "TracerTest.Traced.foo:bar/0" &&
               event[:call_count] == 1
           end)
  end

  test "Trace function with category" do
    TestHelper.restart_harvest_cycle(Collector.CustomEvent.HarvestCycle)

    Traced.query()
    Traced.query()

    TestHelper.trigger_report(NewRelic.Aggregate.Reporter)
    events = TestHelper.gather_harvest(Collector.CustomEvent.Harvester)

    assert Enum.find(events, fn [_, event, _] ->
             event[:category] == :Metric && event[:mfa] == "TracerTest.Traced.query/0" &&
               event[:metric_category] == :external && event[:call_count] == 2
           end)
  end

  test "Default arguments still work as expected" do
    assert 5 == Traced.default(5)
    assert 3 == Traced.default()
  end

  test "Don't warn when tracing with an ignored arg" do
    TestHelper.restart_harvest_cycle(Collector.CustomEvent.HarvestCycle)

    assert Traced.ignored(:arg) == :ignored

    TestHelper.trigger_report(NewRelic.Aggregate.Reporter)
    events = TestHelper.gather_harvest(Collector.CustomEvent.Harvester)

    assert Enum.find(events, fn [_, event, _] ->
             event[:category] == :Metric && event[:mfa] == "TracerTest.Traced.ignored/1" &&
               event[:call_count] == 1
           end)
  end

  test "Handle a struct argument with enforced_keys" do
    TestHelper.restart_harvest_cycle(Collector.CustomEvent.HarvestCycle)

    assert Traced.naive(NaiveDateTime.utc_now()) == :naive

    TestHelper.trigger_report(NewRelic.Aggregate.Reporter)
    events = TestHelper.gather_harvest(Collector.CustomEvent.Harvester)

    assert Enum.find(events, fn [_, event, _] ->
             event[:category] == :Metric && event[:mfa] == "TracerTest.Traced.naive/1" &&
               event[:call_count] == 1
           end)
  end

  test "Handle an assigned & ignored pattern match" do
    TestHelper.restart_harvest_cycle(Collector.CustomEvent.HarvestCycle)

    assert Traced.ignored(:left) == :left
    assert Traced.ignored(:right) == :right

    TestHelper.trigger_report(NewRelic.Aggregate.Reporter)
    events = TestHelper.gather_harvest(Collector.CustomEvent.Harvester)

    assert Enum.find(events, fn [_, event, _] ->
             event[:category] == :Metric && event[:mfa] == "TracerTest.Traced.ignored/1" &&
               event[:call_count] == 2
           end)
  end

  test "Handle module pattern match" do
    TestHelper.restart_harvest_cycle(Collector.CustomEvent.HarvestCycle)

    assert Traced.mod(%Traced{key: :val}) == :val

    TestHelper.trigger_report(NewRelic.Aggregate.Reporter)
    events = TestHelper.gather_harvest(Collector.CustomEvent.Harvester)

    assert Enum.find(events, fn [_, event, _] ->
             event[:category] == :Metric && event[:mfa] == "TracerTest.Traced.mod/1"
           end)
  end

  test "Trace a function with a guard" do
    TestHelper.restart_harvest_cycle(Collector.CustomEvent.HarvestCycle)

    assert Traced.guard(:foo) == :foo

    TestHelper.trigger_report(NewRelic.Aggregate.Reporter)
    events = TestHelper.gather_harvest(Collector.CustomEvent.Harvester)

    assert Enum.find(events, fn [_, event, _] ->
             event[:category] == :Metric && event[:mfa] == "TracerTest.Traced.guard/1" &&
               event[:call_count] == 1
           end)
  end

  test "Trace multiple function heads" do
    TestHelper.restart_harvest_cycle(Collector.CustomEvent.HarvestCycle)

    assert Traced.multi(1, 2) == {10, 2}
    assert Traced.multi(2, 2) == {20, 2}
    assert Traced.multi(4, 2) == {4, 2}
    TestHelper.trigger_report(NewRelic.Aggregate.Reporter)
    events = TestHelper.gather_harvest(Collector.CustomEvent.Harvester)

    assert Enum.find(events, fn [_, event, _] ->
             event[:category] == :Metric &&
               event[:mfa] == "TracerTest.Traced.multi:multiple_function_heads/2" &&
               event[:call_count] == 3
           end)
  end

  test "Trace a private function" do
    TestHelper.restart_harvest_cycle(Collector.CustomEvent.HarvestCycle)

    assert Traced.call_priv() == :priv

    TestHelper.trigger_report(NewRelic.Aggregate.Reporter)
    events = TestHelper.gather_harvest(Collector.CustomEvent.Harvester)

    assert Enum.find(events, fn [_, event, _] ->
             event[:category] == :Metric && event[:mfa] == "TracerTest.Traced.priv/0" &&
               event[:call_count] == 1
           end)
  end

  test "Don't trace when trace is deprecated" do
    TestHelper.restart_harvest_cycle(Collector.Metric.HarvestCycle)

    assert Traced.db_query() == :result

    metrics = TestHelper.gather_harvest(Collector.Metric.Harvester)
    assert metrics == []
  end

  test "Don't track trace segments that are NOT part of a process in a Transaction" do
    Traced.funny()

    assert %{} == NewRelic.Util.AttrStore.collect(NewRelic.Transaction.Reporter, self())
    assert %{} == NewRelic.Util.AttrStore.collect(NewRelic.Transaction.Reporter.Tracking, self())
  end
end
