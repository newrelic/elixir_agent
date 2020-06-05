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

    get "/funky_attrs" do
      NewRelic.add_attributes(
        # allowed:
        one: 1,
        half: 0.5,
        string: "A string",
        bool: true,
        nilValue: nil,
        atom: :atom,
        pid: self(),
        ref: make_ref(),
        port: :erlang.list_to_port('#Port<0.4>'),
        date: Date.utc_today(),
        date_time: DateTime.utc_now(),
        naive_date_time: NaiveDateTime.utc_now(),
        time: Time.utc_now(),
        # not allowed:
        binary: "fooo" |> :zlib.gzip(),
        struct: %NewRelic.Metric{},
        tuple: {:one, :two},
        function: fn -> :fun! end
      )

      send_resp(conn, 200, "funky_attrs")
    end

    get "/service" do
      NewRelic.set_transaction_name("/service")
      NewRelic.add_attributes(query: "query{}")
      ExternalService.query(2)
      ExternalService.query(5)
      send_resp(conn, 200, "service")
    end

    get "/map" do
      NewRelic.add_attributes(plain: "attr", deep: %{foo: %{bar: "baz", baz: "bar"}})
      send_resp(conn, 200, "map")
    end

    get "/sequential/:order" do
      NewRelic.set_transaction_name("/sequential")
      NewRelic.add_attributes(order: order)
      send_resp(conn, 200, "sequential")
    end

    get "/fail" do
      NewRelic.add_attributes(query: "query{}")
      raise "TransactionError"
      send_resp(conn, 200, "won't get here")
    end

    get "/error" do
      Task.Supervisor.async_nolink(TestTaskSup, fn ->
        Process.sleep(20)
        raise "Oops"
      end)

      Process.sleep(30)
      send_resp(conn, 200, "this is fine")
    end

    get "/spawn" do
      # We need to sleep here & there because spawn tracking is async
      Task.async(fn ->
        Process.sleep(20)
        NewRelic.add_attributes(inside: "spawned")

        Task.async(fn ->
          Process.sleep(20)
          NewRelic.add_attributes(nested: "spawn")

          Task.Supervisor.async_nolink(
            TestTaskSup,
            fn ->
              Process.sleep(20)
              NewRelic.add_attributes(not_linked: "still_tracked")

              Task.async(fn ->
                Process.sleep(20)
                NewRelic.add_attributes(nested_inside: "nolink")
              end)
            end
          )

          Task.Supervisor.async_nolink(
            TestTaskSup,
            fn ->
              Process.sleep(20)
              NewRelic.add_attributes(not_tracked: "not_tracked")
            end,
            new_relic: :no_track
          )

          Task.async(fn ->
            Process.sleep(20)
            NewRelic.add_attributes(rabbit: "hole")
          end)
        end)
      end)

      Process.sleep(100)
      send_resp(conn, 200, "spawn")
    end

    get "/ignored" do
      NewRelic.ignore_transaction()
      send_resp(conn, 200, "ignored")
    end

    get "/total_time" do
      Process.sleep(10)

      t1 =
        Task.async(fn ->
          Process.sleep(10)
          ExternalService.query(200)
        end)

      ExternalService.query(200)
      Task.await(t1)

      Process.sleep(10)
      send_resp(conn, 200, "ok")
    end
  end

  test "Basic transaction" do
    TestHelper.restart_harvest_cycle(Collector.TransactionEvent.HarvestCycle)

    TestHelper.request(TestPlugApp, conn(:get, "/foo/1"))

    events = TestHelper.gather_harvest(Collector.TransactionEvent.Harvester)

    assert Enum.find(events, fn [_, event] ->
             event[:path] == "/foo/1" && event[:name] == "/Plug/GET//foo/:blah" &&
               event[:foo] == "BAR" && event[:duration_us] > 0 && event[:duration_us] < 50_000 &&
               event[:start_time] < 2_000_000_000_000 && event[:start_time] > 1_400_000_000_000 &&
               event[:start_time_mono] == nil && event[:test_attribute] == "test_value" &&
               event[:"nr.apdexPerfZone"] == "S" && event[:status] == 200
           end)
  end

  @bad "[BAD_VALUE]"
  test "Attribute coercion" do
    TestHelper.restart_harvest_cycle(Collector.TransactionEvent.HarvestCycle)

    TestHelper.request(TestPlugApp, conn(:get, "/funky_attrs"))

    events = TestHelper.gather_harvest(Collector.TransactionEvent.Harvester)

    [_, event] = Enum.find(events, fn [_, event] -> event[:name] == "/Plug/GET//funky_attrs" end)

    # Basic values
    assert event[:one] == 1
    assert event[:half] == 0.5
    assert event[:bool] == true
    assert event[:string] == "A string"
    assert event[:atom] == "atom"

    # Fancy values
    assert event[:pid] =~ "#PID"
    assert event[:ref] =~ "#Reference"
    assert event[:port] =~ "#Port"
    assert {:ok, _, _} = DateTime.from_iso8601(event[:date_time])
    assert {:ok, _} = NaiveDateTime.from_iso8601(event[:naive_date_time])
    assert {:ok, _} = Date.from_iso8601(event[:date])
    assert {:ok, _} = Time.from_iso8601(event[:time])

    # Bad values
    assert event[:binary] == @bad
    assert event[:tuple] == @bad
    assert event[:function] == @bad
    assert event[:struct] == @bad

    # Don't report nil values
    refute Map.has_key?(event, :nilValue)

    # Make sure it can serialize to JSON
    Jason.encode!(events)
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

  @tag capture_log: true
  test "Failure of the Transaction" do
    TestHelper.restart_harvest_cycle(Collector.TransactionEvent.HarvestCycle)

    TestHelper.request(TestPlugApp, conn(:get, "/fail"))

    events = TestHelper.gather_harvest(Collector.TransactionEvent.Harvester)

    assert Enum.find(events, fn [_, event] ->
             event[:status] == 500 &&
               event[:query] =~ "query{}" &&
               event[:error] &&
               event[:name] == "/Plug/GET//error" &&
               event[:error_reason] =~ "TransactionError" &&
               event[:error_kind] == :exit &&
               event[:error_stack] =~ "test/transaction_test.exs"
           end)
  end

  @tag :capture_log
  test "Error in Transaction" do
    TestHelper.restart_harvest_cycle(Collector.TransactionEvent.HarvestCycle)
    Task.Supervisor.start_link(name: TestTaskSup)

    TestHelper.request(TestPlugApp, conn(:get, "/error"))

    events = TestHelper.gather_harvest(Collector.TransactionEvent.Harvester)

    assert Enum.find(events, fn [_, event] ->
             event[:status] == 200 && event[:error] == nil
           end)
  end

  @tag capture_log: true
  test "Allow disabling error detail collection" do
    Application.put_env(:new_relic_agent, :error_collector_enabled, false)

    TestHelper.restart_harvest_cycle(Collector.TransactionEvent.HarvestCycle)

    TestHelper.request(TestPlugApp, conn(:get, "/fail"))

    events = TestHelper.gather_harvest(Collector.TransactionEvent.Harvester)

    assert Enum.find(events, fn [_, event] ->
             event[:status] == 500 && event[:error] == true && event[:error_reason] == nil &&
               event[:error_kind] == nil && event[:error_stack] == nil
           end)

    Application.delete_env(:new_relic_agent, :error_collector_enabled)
  end

  test "Transaction with traced external service call" do
    TestHelper.trigger_report(NewRelic.Aggregate.Reporter)
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

  test "Track attrs inside proccesses spawned by the transaction" do
    TestHelper.restart_harvest_cycle(Collector.TransactionEvent.HarvestCycle)
    Task.Supervisor.start_link(name: TestTaskSup)

    TestHelper.request(TestPlugApp, conn(:get, "/spawn"))

    events = TestHelper.gather_harvest(Collector.TransactionEvent.Harvester)

    event =
      Enum.find(events, fn [_, event] ->
        event[:path] == "/spawn" && event[:inside] == "spawned" && event[:nested] == "spawn" &&
          event[:not_linked] == "still_tracked" && event[:nested_inside] == "nolink" &&
          event[:rabbit] == "hole" && event[:process_spawns] == 6 && event[:status] == 200
      end)

    assert event

    # Don't track when manually excluded
    refute event[:not_tracked]
  end

  test "Flatten the keys of a nested map into a list of individual attributes" do
    TestHelper.restart_harvest_cycle(Collector.TransactionEvent.HarvestCycle)

    TestHelper.request(TestPlugApp, conn(:get, "/map"))

    events = TestHelper.gather_harvest(Collector.TransactionEvent.Harvester)

    assert Enum.find(events, fn [_, event] ->
             event[:path] == "/map" && event[:plain] == "attr" && event["deep.foo.bar"] == "baz" &&
               event["deep.foo.baz"] == "bar"
           end)
  end

  test "Allow a transaction to be ignored" do
    TestHelper.restart_harvest_cycle(Collector.TransactionEvent.HarvestCycle)
    Task.Supervisor.start_link(name: TestTaskSup)

    TestHelper.request(TestPlugApp, conn(:get, "/ignored"))

    events = TestHelper.gather_harvest(Collector.TransactionEvent.Harvester)

    assert events == []
  end

  test "Calculate total time" do
    TestHelper.restart_harvest_cycle(Collector.TransactionEvent.HarvestCycle)

    TestHelper.request(TestPlugApp, conn(:get, "/total_time"))

    [[_, event]] = TestHelper.gather_harvest(Collector.TransactionEvent.Harvester)

    assert_in_delta event[:duration_s], 0.2, 0.1
    assert_in_delta event[:total_time_s], 0.4, 0.1

    assert event[:total_time_s] > event[:duration_s]
  end

  describe "Request queueing" do
    test "queueDuration is included in the transaction (in seconds)" do
      TestHelper.restart_harvest_cycle(Collector.TransactionEvent.HarvestCycle)

      request_start = System.system_time(:microsecond) - 1_500_000

      conn =
        conn(:get, "/total_time")
        |> put_req_header("x-request-start", "t=#{request_start}")

      TestHelper.request(TestPlugApp, conn)

      [[_, event]] = TestHelper.gather_harvest(Collector.TransactionEvent.Harvester)

      assert_in_delta event[:queueDuration], 1.5, 0.1
    end

    test "account for clock skew - ignore a negative queue duration" do
      TestHelper.restart_harvest_cycle(Collector.TransactionEvent.HarvestCycle)

      # request start somehow is in the future
      request_start = System.system_time(:microsecond) + 100_000

      conn =
        conn(:get, "/total_time")
        |> put_req_header("x-request-start", "t=#{request_start}")

      TestHelper.request(TestPlugApp, conn)

      [[_, event]] = TestHelper.gather_harvest(Collector.TransactionEvent.Harvester)

      assert event[:queueDuration] == 0
    end
  end
end
