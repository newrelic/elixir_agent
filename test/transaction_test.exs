defmodule TransactionTest do
  use ExUnit.Case
  use Plug.Test

  alias NewRelic.Harvest.Collector

  defmodule HelperModule do
    use NewRelic.Tracer
    @trace :function
    def function(n), do: Process.sleep(n)
  end

  defmodule ExternalService do
    use NewRelic.Tracer
    @trace {:query, category: :external}
    def query(n), do: Process.sleep(n)
  end

  defmodule TestPlugApp do
    use Plug.Router
    use NewRelic.Transaction

    plug(:match)
    plug(:dispatch)

    get "/foo/:blah" do
      NewRelic.add_attributes(foo: "BAR")
      NewRelic.incr_attributes(one: 1, two: 1)
      NewRelic.incr_attributes(two: 1)
      send_resp(conn, 200, "bar")
    end

    get "/incr" do
      NewRelic.set_transaction_name("/incr")
      NewRelic.incr_attributes(one: 1, two: 1, four: 2)
      NewRelic.incr_attributes(two: 1, four: 2.0)
      send_resp(conn, 200, "incr")
    end

    get "/service" do
      NewRelic.set_transaction_name("/service")
      NewRelic.add_attributes(query: "query{}")
      ExternalService.query(2)
      ExternalService.query(5)
      send_resp(conn, 200, "service")
    end

    get "/sequential/:order" do
      NewRelic.set_transaction_name("/sequential")
      NewRelic.add_attributes(order: order)
      send_resp(conn, 200, "sequential")
    end

    get "/error" do
      NewRelic.add_attributes(query: "query{}")
      raise "TransactionError"
      send_resp(conn, 200, "won't get here")
    end

    get "/spawn" do
      # We need to sleep here & there because spawn tracking is async
      Task.async(fn ->
        Process.sleep(20)
        NewRelic.add_attributes(inside: "spawned")

        Task.async(fn ->
          Process.sleep(20)
          NewRelic.add_attributes(nested: "spawn")

          Task.Supervisor.async_nolink(TestTaskSup, fn ->
            Process.sleep(20)
            NewRelic.add_attributes(not_linked: "still_tracked")

            Task.async(fn ->
              Process.sleep(20)
              NewRelic.add_attributes(nested_inside: "nolink")
            end)
          end)

          Task.async(fn ->
            Process.sleep(20)
            NewRelic.add_attributes(rabbit: "hole")
          end)
        end)
      end)

      Process.sleep(100)
      send_resp(conn, 200, "spawn")
    end
  end

  test "Basic transaction" do
    TestHelper.restart_harvest_cycle(Collector.TransactionEvent.HarvestCycle)

    TestHelper.request(TestPlugApp, conn(:get, "/foo/1"))

    events = TestHelper.gather_harvest(Collector.TransactionEvent.Harvester)

    assert Enum.find(events, fn [_, event] ->
             event[:path] == "/foo/1" && event[:name] == "/Plug/GET//foo/:blah" &&
               event[:foo] == "BAR" && event[:duration_us] > 0 && event[:duration_us] < 5000 &&
               event[:start_time] < 2_000_000_000_000 && event[:start_time] > 1_400_000_000_000 &&
               event[:start_time_mono] == nil && event[:test_attribute] == "test_value" &&
               event[:status] == 200
           end)
  end

  test "Incrementing attribute counters" do
    TestHelper.restart_harvest_cycle(Collector.TransactionEvent.HarvestCycle)

    TestHelper.request(TestPlugApp, conn(:get, "/incr"))

    events = TestHelper.gather_harvest(Collector.TransactionEvent.Harvester)

    assert Enum.find(events, fn [_, event] ->
             event[:path] == "/incr" && event[:one] == 1 && event[:two] == 2 &&
               event[:four] === 4.0 && event[:status] == 200
           end)
  end

  test "Error in Transaction" do
    TestHelper.restart_harvest_cycle(Collector.TransactionEvent.HarvestCycle)

    assert_raise RuntimeError, fn ->
      TestPlugApp.call(conn(:get, "/error"), [])
    end

    events = TestHelper.gather_harvest(Collector.TransactionEvent.Harvester)

    assert Enum.find(events, fn [_, event] ->
             event[:status] == 500 && event[:query] =~ "query{}" &&
               event[:error_reason] =~ "TransactionError"
           end)
  end

  test "Transaction with traced external service call" do
    TestHelper.restart_harvest_cycle(Collector.TransactionEvent.HarvestCycle)
    TestHelper.restart_harvest_cycle(Collector.CustomEvent.HarvestCycle)

    TestHelper.request(TestPlugApp, conn(:get, "/service"))

    TestHelper.trigger_report(NewRelic.Aggregate.Reporter)

    events = TestHelper.gather_harvest(Collector.CustomEvent.Harvester)
    tx_events = TestHelper.gather_harvest(Collector.TransactionEvent.Harvester)

    refute Enum.find(events, fn [_, event, _] -> event[:query] == "query" end)

    assert Enum.find(tx_events, fn [_, event] ->
             event[:path] == "/service" && event[:external_call_count] == 2 &&
               event[:"external.TransactionTest.ExternalService.query.call_count"] == 2 &&
               event[:status] == 200
           end)

    assert Enum.find(events, fn [_, event, _] ->
             event[:category] == :Metric && event[:name] == :FunctionTrace &&
               event[:mfa] == "TransactionTest.ExternalService.query/1" && event[:call_count] == 2
           end)

    assert Enum.find(events, fn [_, event, _] ->
             event[:category] == :Metric && event[:type] == :Transaction &&
               event[:name] == "/service" && event[:call_count] == 1
           end)
  end

  test "Multiple sequential transactions in the same process" do
    TestHelper.restart_harvest_cycle(Collector.TransactionEvent.HarvestCycle)

    Task.async(fn ->
      TestPlugApp.call(conn(:get, "/sequential/1"), [])
      TestPlugApp.call(conn(:get, "/sequential/2"), [])
      TestPlugApp.call(conn(:get, "/sequential/3"), [])
    end)
    |> Task.await()

    TestHelper.trigger_report(NewRelic.Aggregate.Reporter)
    events = TestHelper.gather_harvest(Collector.TransactionEvent.Harvester)

    assert Enum.find(events, fn [_, event] ->
             event[:path] == "/sequential/1" && event[:order] == "1" && event[:status] == 200
           end)

    assert Enum.find(events, fn [_, event] ->
             event[:path] == "/sequential/2" && event[:order] == "2" && event[:status] == 200
           end)

    assert Enum.find(events, fn [_, event] ->
             event[:path] == "/sequential/3" && event[:order] == "3" && event[:status] == 200
           end)
  end

  test "Track attrs inside proccesses spawned by the transaction" do
    TestHelper.restart_harvest_cycle(Collector.TransactionEvent.HarvestCycle)
    Task.Supervisor.start_link(name: TestTaskSup)

    TestHelper.request(TestPlugApp, conn(:get, "/spawn"))

    events = TestHelper.gather_harvest(Collector.TransactionEvent.Harvester)

    assert Enum.find(events, fn [_, event] ->
             event[:path] == "/spawn" && event[:inside] == "spawned" && event[:nested] == "spawn" &&
               event[:not_linked] == "still_tracked" && event[:nested_inside] == "nolink" &&
               event[:rabbit] == "hole" && event[:status] == 200
           end)
  end
end
