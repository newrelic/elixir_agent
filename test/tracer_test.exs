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

    @enforce_keys [:key, :second_key]
    defstruct [:key, :second_key]

    @trace :mod
    def mod(%__MODULE__{key: val}), do: val

    @trace :rescuer
    def rescuer() do
      :do_something
    rescue
      error -> error
    end

    @trace :afterer
    def afterer() do
      :do_something
    rescue
      error -> error
    after
      :do_after
    end

    def non_traced_with_rescue() do
      :do_somthing
    rescue
      error -> error
    end
  end

  setup do
    TestHelper.restart_harvest_cycle(Collector.Metric.HarvestCycle)
  end

  test "function that has error" do
    assert_raise(RuntimeError, fn ->
      Traced.error(RuntimeError)
    end)

    metrics = TestHelper.gather_harvest(Collector.Metric.Harvester)

    assert TestHelper.find_metric(metrics, "Function/TracerTest.Traced.error/1")
  end

  test "function with function head" do
    assert :default_val == Traced.default_multiclause()
    assert :case_1_return == Traced.default_multiclause(:case_1)
    assert :regular_call == Traced.default_multiclause(:regular_call)

    metrics = TestHelper.gather_harvest(Collector.Metric.Harvester)

    assert TestHelper.find_metric(metrics, "Function/TracerTest.Traced.default_multiclause/1", 3)
  end

  test "Basic traced function" do
    Traced.fun()

    metrics = TestHelper.gather_harvest(Collector.Metric.Harvester)

    assert TestHelper.find_metric(metrics, "Function/TracerTest.Traced.fun/0")
  end

  test "Trace function with additional name" do
    Traced.foo()

    metrics = TestHelper.gather_harvest(Collector.Metric.Harvester)

    assert TestHelper.find_metric(metrics, "Function/TracerTest.Traced.foo:bar/0")
  end

  test "Trace categorized as External" do
    Traced.query()
    Traced.query()

    metrics = TestHelper.gather_harvest(Collector.Metric.Harvester)

    assert TestHelper.find_metric(metrics, "External/TracerTest.Traced.query/all", 2)
  end

  test "Default arguments still work as expected" do
    assert 5 == Traced.default(5)
    assert 3 == Traced.default()
  end

  test "Don't warn when tracing with an ignored arg" do
    assert Traced.ignored(:arg) == :ignored

    metrics = TestHelper.gather_harvest(Collector.Metric.Harvester)

    assert TestHelper.find_metric(metrics, "Function/TracerTest.Traced.ignored/1")
  end

  test "Handle a struct argument with enforced_keys" do
    assert Traced.naive(NaiveDateTime.utc_now()) == :naive

    metrics = TestHelper.gather_harvest(Collector.Metric.Harvester)

    assert TestHelper.find_metric(metrics, "Function/TracerTest.Traced.naive/1")
  end

  test "Handle an assigned & ignored pattern match" do
    assert Traced.ignored(:left) == :left
    assert Traced.ignored(:right) == :right

    metrics = TestHelper.gather_harvest(Collector.Metric.Harvester)

    assert TestHelper.find_metric(metrics, "Function/TracerTest.Traced.ignored/1", 2)
  end

  test "Handle module pattern match" do
    assert Traced.mod(%Traced{key: :val, second_key: :bla}) == :val

    metrics = TestHelper.gather_harvest(Collector.Metric.Harvester)

    assert TestHelper.find_metric(metrics, "Function/TracerTest.Traced.mod/1")
  end

  test "Trace a function with a guard" do
    assert Traced.guard(:foo) == :foo

    metrics = TestHelper.gather_harvest(Collector.Metric.Harvester)

    assert TestHelper.find_metric(metrics, "Function/TracerTest.Traced.guard/1")
  end

  test "Trace multiple function heads" do
    assert Traced.multi(1, 2) == {10, 2}
    assert Traced.multi(2, 2) == {20, 2}
    assert Traced.multi(4, 2) == {4, 2}

    metrics = TestHelper.gather_harvest(Collector.Metric.Harvester)

    assert TestHelper.find_metric(
             metrics,
             "Function/TracerTest.Traced.multi:multiple_function_heads/2",
             3
           )
  end

  test "Trace a private function" do
    assert Traced.call_priv() == :priv

    metrics = TestHelper.gather_harvest(Collector.Metric.Harvester)

    assert TestHelper.find_metric(metrics, "Function/TracerTest.Traced.priv/0")
  end

  test "Don't trace when trace is deprecated" do
    assert Traced.db_query() == :result

    metrics = TestHelper.gather_harvest(Collector.Metric.Harvester)
    refute Enum.any?(metrics, fn [%{name: name}, _] -> name =~ "db_query" end)
  end
end
