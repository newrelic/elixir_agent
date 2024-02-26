defmodule ErrorTest do
  use ExUnit.Case
  import ExUnit.CaptureLog
  alias NewRelic.Harvest.Collector

  defmodule ErrorDummy do
    use GenServer
    def init(args), do: {:ok, args}
    def start_link, do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
    @compile {:no_warn_undefined, Not}
    def handle_call(:nofun, _from, _state), do: Not.a_function(:one, :two)
    def handle_call(:secretfun, _from, _state), do: Not.secretfun("secretvalue", "other_secret")
    def handle_call(:sleep, _from, _state), do: :timer.sleep(:infinity)
    def handle_call(:raise, _from, _state), do: raise("ERROR")
    def handle_call(:erlang_error, _from, _state), do: raise(:erlang.error(:badarg))
  end

  test "Catch and harvest errors" do
    Process.flag(:trap_exit, true)
    TestHelper.restart_harvest_cycle(Collector.TransactionErrorEvent.HarvestCycle)
    ErrorDummy.start_link()

    capture_log(fn ->
      catch_exit do
        GenServer.call(ErrorDummy, :nofun)
      end
    end)

    events = TestHelper.gather_harvest(Collector.TransactionErrorEvent.Harvester)

    assert Enum.find(events, fn [intrinsic, _, _] ->
             intrinsic[:"error.class"] == "UndefinedFunctionError"
           end)
  end

  test "Redact arguments when not gathering stacktrace args" do
    Process.flag(:trap_exit, true)
    TestHelper.restart_harvest_cycle(Collector.TransactionErrorEvent.HarvestCycle)
    TestHelper.restart_harvest_cycle(Collector.ErrorTrace.HarvestCycle)
    ErrorDummy.start_link()

    reset_features = TestHelper.update(:nr_features, stacktrace_argument_collection: false)

    capture_log(fn ->
      catch_exit do
        GenServer.call(ErrorDummy, :secretfun)
      end
    end)

    [[_, event_error, _]] = TestHelper.gather_harvest(Collector.TransactionErrorEvent.Harvester)
    [[_, _, _, _, trace_error, _]] = TestHelper.gather_harvest(Collector.ErrorTrace.Harvester)

    refute String.contains?(event_error.stacktrace, "secretvalue")
    refute String.contains?(event_error.stacktrace, "other_secret")
    assert String.contains?(event_error.stacktrace, "Not.secretfun(\"DISABLED (arity: 2)\")")

    refute String.contains?(List.first(trace_error.stack_trace), "secretvalue")
    refute String.contains?(List.first(trace_error.stack_trace), "other_secret")

    assert String.contains?(
             List.first(trace_error.stack_trace),
             "Not.secretfun(\"DISABLED (arity: 2)\")"
           )

    reset_features.()
  end

  test "Catch a raised Error" do
    Process.flag(:trap_exit, true)
    TestHelper.restart_harvest_cycle(Collector.TransactionErrorEvent.HarvestCycle)
    ErrorDummy.start_link()

    capture_log(fn ->
      catch_exit do
        GenServer.call(ErrorDummy, :raise)
      end
    end)

    events = TestHelper.gather_harvest(Collector.TransactionErrorEvent.Harvester)

    assert Enum.find(events, fn [intrinsic, _, _] ->
             intrinsic[:"error.message"] =~ "ERROR"
           end)
  end

  test "Catch a GenServer timeout error" do
    TestHelper.restart_harvest_cycle(Collector.TransactionErrorEvent.HarvestCycle)
    ErrorDummy.start_link()

    :proc_lib.spawn(fn ->
      GenServer.call(ErrorDummy, :sleep, 50)
    end)

    :timer.sleep(100)

    events = TestHelper.gather_harvest(Collector.TransactionErrorEvent.Harvester)

    assert Enum.find(events, fn [intrinsic, _, _] ->
             intrinsic[:"error.class"] == "EXIT" &&
               intrinsic[:"error.message"] == "(GenServer.call/3) :timeout"
           end)
  end

  test "Catch an erlang :badarg error" do
    TestHelper.restart_harvest_cycle(Collector.TransactionErrorEvent.HarvestCycle)

    :proc_lib.spawn(fn ->
      :erlang.error(:badarg)
    end)

    :timer.sleep(100)

    events = TestHelper.gather_harvest(Collector.TransactionErrorEvent.Harvester)

    assert Enum.find(events, fn [intrinsic, _, _] ->
             intrinsic[:"error.class"] == "ArgumentError"
           end)
  end

  test "Handle Erlang exception when stacktrace arg colleection is turned off" do
    Process.flag(:trap_exit, true)
    TestHelper.restart_harvest_cycle(Collector.TransactionErrorEvent.HarvestCycle)
    TestHelper.restart_harvest_cycle(Collector.ErrorTrace.HarvestCycle)
    ErrorDummy.start_link()

    reset_features = TestHelper.update(:nr_features, stacktrace_argument_collection: false)

    capture_log(fn ->
      catch_exit do
        GenServer.call(ErrorDummy, :erlang_error)
      end
    end)

    [[_, event_error, _]] = TestHelper.gather_harvest(Collector.TransactionErrorEvent.Harvester)

    assert String.contains?(event_error.stacktrace, "init(\"DISABLED (arity: 1)\")")

    reset_features.()
  end

  test "Catch a simple raise" do
    TestHelper.restart_harvest_cycle(Collector.TransactionErrorEvent.HarvestCycle)

    :proc_lib.spawn(fn ->
      raise "RAISE"
    end)

    :timer.sleep(100)

    events = TestHelper.gather_harvest(Collector.TransactionErrorEvent.Harvester)

    assert Enum.find(events, fn [intrinsic, _, _] ->
             intrinsic[:"error.message"] =~ "RAISE"
           end)
  end

  test "Nicely format EXIT when it's an exception struct" do
    TestHelper.restart_harvest_cycle(Collector.TransactionErrorEvent.HarvestCycle)

    :proc_lib.spawn(fn ->
      exit(%RuntimeError{message: "foo"})
    end)

    :timer.sleep(100)

    events = TestHelper.gather_harvest(Collector.TransactionErrorEvent.Harvester)

    assert Enum.find(events, fn [intrinsic, _, _] ->
             intrinsic[:"error.class"] == "EXIT" &&
               intrinsic[:"error.message"] == "(RuntimeError) foo"
           end)
  end

  test "Catch a file error" do
    TestHelper.restart_harvest_cycle(Collector.TransactionErrorEvent.HarvestCycle)

    :proc_lib.spawn(fn ->
      File.read!("no_file")
    end)

    :timer.sleep(100)

    events = TestHelper.gather_harvest(Collector.TransactionErrorEvent.Harvester)

    assert Enum.find(events, fn [intrinsic, _, _] ->
             intrinsic[:"error.class"] == "File.Error"
           end)
  end

  test "Catch a function clause error inside a Task" do
    TestHelper.restart_harvest_cycle(Collector.TransactionErrorEvent.HarvestCycle)

    :proc_lib.spawn(fn ->
      Task.async(fn -> ErrorDummy.handle_call(:foo, nil, nil) end) |> Task.await()
    end)

    :timer.sleep(100)

    events = TestHelper.gather_harvest(Collector.TransactionErrorEvent.Harvester)

    assert Enum.find(events, fn [intrinsic, _, _] ->
             intrinsic[:"error.class"] == "FunctionClauseError"
           end)
  end
end
