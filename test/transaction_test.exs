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

    get "/erlang_exit" do
      NewRelic.add_attributes(query: "query{}")
      :erlang.exit(:something_bad)
      send_resp(conn, 200, "won't get here")
    end

    get "/await_timeout" do
      Task.async(fn ->
        Process.sleep(100)
      end)
      |> Task.await(10)

      send_resp(conn, 200, "won't get here")
    end

    get "/spawn" do
      Task.async(fn ->
        NewRelic.add_attributes(inside: "spawned")

        Task.async(fn ->
          NewRelic.add_attributes(nested: "spawn")

          Task.Supervisor.async_nolink(
            TestTaskSup,
            fn ->
              NewRelic.connect_task_to_transaction()
              NewRelic.add_attributes(not_linked: "still_tracked")
              Process.sleep(5)

              Task.async(fn ->
                NewRelic.add_attributes(nested_inside: "nolink")

                Process.sleep(5)
              end)
              |> Task.await()
            end
          )

          Task.Supervisor.async_nolink(
            TestTaskSup,
            fn ->
              NewRelic.add_attributes(not_tracked: "not_tracked")

              Process.sleep(5)
            end
          )

          Task.async(fn ->
            NewRelic.add_attributes(rabbit: "hole")

            Process.sleep(5)
          end)
          |> Task.await()

          Process.sleep(5)
        end)

        Process.sleep(5)
      end)
      |> Task.await()

      Process.sleep(50)
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

    get "/slow" do
      Process.sleep(1_000)
      send_resp(conn, 200, "finally")
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
               event[:name] == "/Plug/GET//fail" &&
               event[:error_reason] =~ "TransactionError" &&
               event[:error_kind] == :exit &&
               event[:error_stack] =~ "test/transaction_test.exs"
           end)
  end

  @tag capture_log: true
  test "Failure of the Transaction - erlang exit" do
    TestHelper.restart_harvest_cycle(Collector.TransactionEvent.HarvestCycle)

    TestHelper.request(TestPlugApp, conn(:get, "/erlang_exit"))

    events = TestHelper.gather_harvest(Collector.TransactionEvent.Harvester)

    assert Enum.find(events, fn [_, event] ->
             event[:status] == 500 &&
               event[:query] =~ "query{}" &&
               event[:error] &&
               event[:name] == "/Plug/GET//erlang_exit" &&
               event[:error_reason] =~ "something_bad" &&
               event[:error_kind] == :exit
           end)
  end

  @tag capture_log: true
  test "Failure of the Transaction - await timeout" do
    TestHelper.restart_harvest_cycle(Collector.TransactionEvent.HarvestCycle)

    TestHelper.request(TestPlugApp, conn(:get, "/await_timeout"))

    events = TestHelper.gather_harvest(Collector.TransactionEvent.Harvester)

    assert Enum.find(events, fn [_, event] ->
             event[:status] == 500 &&
               event[:error] &&
               event[:name] == "/Plug/GET//await_timeout" &&
               event[:error_reason] =~ "timeout" &&
               event[:error_kind] == :exit
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
    reset_features = TestHelper.update(:nr_features, error_collector: false)

    TestHelper.restart_harvest_cycle(Collector.TransactionEvent.HarvestCycle)

    TestHelper.request(TestPlugApp, conn(:get, "/fail"))

    events = TestHelper.gather_harvest(Collector.TransactionEvent.Harvester)

    assert Enum.find(events, fn [_, event] ->
             event[:status] == 500 && event[:error] == true && event[:error_reason] == nil &&
               event[:error_kind] == nil && event[:error_stack] == nil
           end)

    reset_features.()
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
          event[:rabbit] == "hole" && event[:status] == 200
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

    assert %{status_code: 200} = TestHelper.request(TestPlugApp, conn(:get, "/ignored"))

    events = TestHelper.gather_harvest(Collector.TransactionEvent.Harvester)

    assert events == []
  end

  test "Calculate total time" do
    TestHelper.restart_harvest_cycle(Collector.TransactionEvent.HarvestCycle)

    TestHelper.request(TestPlugApp, conn(:get, "/total_time"))

    [[_, event]] = TestHelper.gather_harvest(Collector.TransactionEvent.Harvester)

    assert event[:duration_s] >= 0.220
    assert event[:total_time_s] >= 0.420

    assert event[:total_time_s] > event[:duration_s]
    assert event[:total_time_s] < event[:duration_s] * 2

    assert event[:process_spawns] == 1
  end

  describe "Request queuing" do
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

    test "Controlled via config" do
      reset_features = TestHelper.update(:nr_features, request_queuing_metrics: false)
      TestHelper.restart_harvest_cycle(Collector.TransactionEvent.HarvestCycle)

      request_start = System.system_time(:microsecond) - 1_500_000

      conn =
        conn(:get, "/total_time")
        |> put_req_header("x-request-start", "t=#{request_start}")

      TestHelper.request(TestPlugApp, conn)

      [[_, event]] = TestHelper.gather_harvest(Collector.TransactionEvent.Harvester)

      refute event[:queueDuration]

      reset_features.()
    end
  end

  test "Client timeout" do
    TestHelper.restart_harvest_cycle(Collector.TransactionEvent.HarvestCycle)

    conn = conn(:get, "/slow")

    {:error, :timeout} = TestHelper.request(TestPlugApp, conn, timeout: 10)

    [[_, event]] = TestHelper.gather_harvest(Collector.TransactionEvent.Harvester)

    assert event[:"cowboy.socket_error"] == "closed"
  end

  test "Server timeout" do
    TestHelper.restart_harvest_cycle(Collector.TransactionEvent.HarvestCycle)

    conn = conn(:get, "/slow")

    {:error, :socket_closed_remotely} =
      TestHelper.request(TestPlugApp, conn, [], idle_timeout: 500)

    [[_, event]] = TestHelper.gather_harvest(Collector.TransactionEvent.Harvester)

    assert event[:"cowboy.connection_error"] == "timeout"
  end
end
