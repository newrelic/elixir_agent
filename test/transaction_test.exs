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

    get "/fn_trace" do
      HelperModule.function(10)
      send_resp(conn, 200, "fn_trace")
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
        port: :erlang.list_to_port(~c"#Port<0.4>"),
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

          tx = NewRelic.get_transaction()

          Task.Supervisor.async_nolink(
            TestTaskSup,
            fn ->
              NewRelic.connect_to_transaction(tx)
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

    get "/ignore/this" do
      send_resp(conn, 200, "ignore me!")
    end

    get "/ignore/these/too" do
      send_resp(conn, 200, "ignore me!")
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

  setup do
    TestHelper.restart_harvest_cycle(Collector.TransactionEvent.HarvestCycle)
    :ok
  end

  test "Basic transaction" do
    TestHelper.request(TestPlugApp, conn(:get, "/foo/1"))

    events = TestHelper.gather_harvest(Collector.TransactionEvent.Harvester)

    event = TestHelper.find_event(events, %{name: "/Plug/GET/foo/:blah"})

    assert event[:path] == "/foo/1"
    assert event[:name] == "/Plug/GET/foo/:blah"
    assert event[:foo] == "BAR"
    assert event[:duration_us] > 0
    assert event[:duration_us] < 50_000
    assert event[:start_time] < 2_000_000_000_000
    assert event[:start_time] > 1_400_000_000_000
    assert event[:start_time_mono] == nil
    assert event[:test_attribute] == "test_value"
    assert event[:"nr.apdexPerfZone"] == "S"
    assert event[:status] == 200
  end

  test "Attribute coercion" do
    TestHelper.request(TestPlugApp, conn(:get, "/funky_attrs"))

    events = TestHelper.gather_harvest(Collector.TransactionEvent.Harvester)

    event = TestHelper.find_event(events, %{name: "/Plug/GET/funky_attrs"})

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

    # Binary values
    assert event[:binary] == "[BINARY_VALUE]"

    # Bad values
    assert event[:tuple] == "[BAD_VALUE]"
    assert event[:function] == "[BAD_VALUE]"
    assert event["struct.__struct__"] == "NewRelic.Metric"

    # Don't report nil values
    refute Map.has_key?(event, :nilValue)

    # Make sure it can serialize to JSON
    NewRelic.JSON.encode!(events)
  end

  test "Incrementing attribute counters" do
    TestHelper.request(TestPlugApp, conn(:get, "/incr"))

    events = TestHelper.gather_harvest(Collector.TransactionEvent.Harvester)

    event = TestHelper.find_event(events, %{path: "/incr"})

    assert event[:one] == 1
    assert event[:two] == 2
    assert event[:four] === 4.0
    assert event[:status] == 200
  end

  @tag capture_log: true
  test "Failure of the Transaction" do
    TestHelper.request(TestPlugApp, conn(:get, "/fail"))

    events = TestHelper.gather_harvest(Collector.TransactionEvent.Harvester)

    event = TestHelper.find_event(events, %{name: "/Plug/GET/fail"})

    assert event[:status] == 500
    assert event[:query] =~ "query{}"
    assert event[:error]
    assert event[:error_reason] =~ "TransactionError"
    assert event[:error_kind] == :exit
    assert event[:error_stack] =~ "test/transaction_test.exs"
  end

  @tag capture_log: true
  test "Failure of the Transaction - erlang exit" do
    TestHelper.request(TestPlugApp, conn(:get, "/erlang_exit"))

    events = TestHelper.gather_harvest(Collector.TransactionEvent.Harvester)

    event = TestHelper.find_event(events, %{name: "/Plug/GET/erlang_exit"})

    assert event[:status] == 500
    assert event[:query] =~ "query{}"
    assert event[:error]
    assert event[:error_reason] =~ "something_bad"
    assert event[:error_kind] == :exit
  end

  @tag capture_log: true
  test "Failure of the Transaction - await timeout" do
    TestHelper.request(TestPlugApp, conn(:get, "/await_timeout"))

    events = TestHelper.gather_harvest(Collector.TransactionEvent.Harvester)

    event = TestHelper.find_event(events, %{name: "/Plug/GET/await_timeout"})

    assert event[:status] == 500
    assert event[:error]
    assert event[:error_reason] =~ "timeout"
    assert event[:error_kind] == :exit
  end

  @tag :capture_log
  test "Error in Transaction" do
    Task.Supervisor.start_link(name: TestTaskSup)

    TestHelper.request(TestPlugApp, conn(:get, "/error"))

    events = TestHelper.gather_harvest(Collector.TransactionEvent.Harvester)

    event = TestHelper.find_event(events, %{name: "/Plug/GET/error"})

    assert event[:status] == 200
    assert event[:error] == nil
  end

  @tag capture_log: true
  test "Allow disabling error detail collection" do
    TestHelper.run_with(:nr_features, error_collector: false)

    TestHelper.request(TestPlugApp, conn(:get, "/fail"))

    events = TestHelper.gather_harvest(Collector.TransactionEvent.Harvester)

    event = TestHelper.find_event(events, %{name: "/Plug/GET/fail"})

    assert event[:status] == 500
    assert event[:error] == true
    refute event[:error_reason]
    refute event[:error_kind]
    refute event[:error_stack]
  end

  test "Transaction with traced external service call" do
    TestHelper.trigger_report(NewRelic.Aggregate.Reporter)
    TestHelper.restart_harvest_cycle(Collector.CustomEvent.HarvestCycle)

    TestHelper.request(TestPlugApp, conn(:get, "/service"))

    TestHelper.trigger_report(NewRelic.Aggregate.Reporter)

    custom_events = TestHelper.gather_harvest(Collector.CustomEvent.Harvester)
    events = TestHelper.gather_harvest(Collector.TransactionEvent.Harvester)

    refute TestHelper.find_event(custom_events, %{query: "query"})

    event = TestHelper.find_event(events, %{name: "/Plug/GET/service"})

    assert event[:path] == "/service"
    assert event[:external_call_count] == 2
    assert event[:"external.TransactionTest.ExternalService.query.call_count"] == 2
    assert event[:status] == 200
  end

  test "Track attrs inside proccesses spawned by the transaction" do
    Task.Supervisor.start_link(name: TestTaskSup)

    TestHelper.request(TestPlugApp, conn(:get, "/spawn"))

    events = TestHelper.gather_harvest(Collector.TransactionEvent.Harvester)

    event = TestHelper.find_event(events, %{name: "/Plug/GET/spawn"})

    assert event[:path] == "/spawn"
    assert event[:inside] == "spawned"
    assert event[:nested] == "spawn"
    assert event[:not_linked] == "still_tracked"
    assert event[:nested_inside] == "nolink"
    assert event[:rabbit] == "hole"
    assert event[:status] == 200

    # Don't track when manually excluded
    refute event[:not_tracked]
  end

  test "Flatten the keys of a nested map into a list of individual attributes" do
    TestHelper.request(TestPlugApp, conn(:get, "/map"))

    events = TestHelper.gather_harvest(Collector.TransactionEvent.Harvester)

    event = TestHelper.find_event(events, %{name: "/Plug/GET/map"})

    assert event[:path] == "/map"
    assert event[:plain] == "attr"
    assert event["deep.foo.bar"] == "baz"
    assert event["deep.foo.baz"] == "bar"
  end

  test "Support setting host display name" do
    TestHelper.run_with(:nr_config, host_display_name: "my-test-host")

    TestHelper.request(TestPlugApp, conn(:get, "/map"))

    events = TestHelper.gather_harvest(Collector.TransactionEvent.Harvester)

    event = TestHelper.find_event(events, %{name: "/Plug/GET/map"})

    assert event[:path] == "/map"
    assert event[:"host.displayName"] == "my-test-host"
  end

  test "Allow a transaction to be ignored" do
    Task.Supervisor.start_link(name: TestTaskSup)

    assert %{status_code: 200} = TestHelper.request(TestPlugApp, conn(:get, "/ignored"))

    events = TestHelper.gather_harvest(Collector.TransactionEvent.Harvester)

    assert events == []
  end

  test "Allow a transaction to be ignored via configuration" do
    Task.Supervisor.start_link(name: TestTaskSup)

    assert %{status_code: 200} = TestHelper.request(TestPlugApp, conn(:get, "/ignore/this"))
    assert %{status_code: 200} = TestHelper.request(TestPlugApp, conn(:get, "/ignore/these/too"))

    events = TestHelper.gather_harvest(Collector.TransactionEvent.Harvester)
    assert events == []
  end

  test "Calculate total time" do
    TestHelper.request(TestPlugApp, conn(:get, "/total_time"))

    events = TestHelper.gather_harvest(Collector.TransactionEvent.Harvester)
    event = TestHelper.find_event(events, %{name: "/Plug/GET/total_time"})

    assert event[:duration_s] >= 0.220
    assert event[:total_time_s] >= 0.420

    assert event[:total_time_s] > event[:duration_s]
    assert event[:total_time_s] < event[:duration_s] * 2

    assert event[:process_spawns] == 2
  end

  describe "Request queuing" do
    test "queueDuration is included in the transaction (in seconds)" do
      request_start = System.system_time(:microsecond) - 1_500_000

      conn =
        conn(:get, "/total_time")
        |> put_req_header("x-request-start", "t=#{request_start}")

      TestHelper.request(TestPlugApp, conn)

      events = TestHelper.gather_harvest(Collector.TransactionEvent.Harvester)
      event = TestHelper.find_event(events, %{name: "/Plug/GET/total_time"})

      assert_in_delta event[:queueDuration], 1.5, 0.1
    end

    test "account for clock skew - ignore a negative queue duration" do
      # request start somehow is in the future
      request_start = System.system_time(:microsecond) + 100_000

      conn =
        conn(:get, "/total_time")
        |> put_req_header("x-request-start", "t=#{request_start}")

      TestHelper.request(TestPlugApp, conn)

      events = TestHelper.gather_harvest(Collector.TransactionEvent.Harvester)
      event = TestHelper.find_event(events, %{name: "/Plug/GET/total_time"})

      assert event[:queueDuration] == 0
    end

    test "Controlled via config" do
      TestHelper.run_with(:nr_features, request_queuing_metrics: false)

      request_start = System.system_time(:microsecond) - 1_500_000

      conn =
        conn(:get, "/total_time")
        |> put_req_header("x-request-start", "t=#{request_start}")

      TestHelper.request(TestPlugApp, conn)

      events = TestHelper.gather_harvest(Collector.TransactionEvent.Harvester)
      event = TestHelper.find_event(events, %{name: "/Plug/GET/total_time"})

      refute event[:queueDuration]
    end
  end

  test "Client timeout" do
    conn = conn(:get, "/slow")

    {:error, :timeout} = TestHelper.request(TestPlugApp, conn, timeout: 10)

    events = TestHelper.gather_harvest(Collector.TransactionEvent.Harvester)
    event = TestHelper.find_event(events, %{name: "/Plug/GET/slow"})

    assert event[:"cowboy.socket_error"] == "closed"
  end

  test "Server timeout" do
    conn = conn(:get, "/slow")

    {:error, :socket_closed_remotely} =
      TestHelper.request(TestPlugApp, conn, [], idle_timeout: 500)

    events = TestHelper.gather_harvest(Collector.TransactionEvent.Harvester)
    event = TestHelper.find_event(events, %{name: "/Plug/GET/slow"})

    assert event[:"cowboy.connection_error"] == "timeout"
  end

  describe "Extended attributes" do
    test "can be turned on" do
      TestHelper.run_with(:nr_features, extended_attributes: true)

      TestHelper.request(TestPlugApp, conn(:get, "/fn_trace"))

      events = TestHelper.gather_harvest(Collector.TransactionEvent.Harvester)
      event = TestHelper.find_event(events, %{name: "/Plug/GET/fn_trace"})

      assert event[:"function.TransactionTest.HelperModule.function/1.call_count"] == 1
    end

    test "can be turned off" do
      TestHelper.run_with(:nr_features, extended_attributes: false)

      TestHelper.request(TestPlugApp, conn(:get, "/fn_trace"))

      events = TestHelper.gather_harvest(Collector.TransactionEvent.Harvester)
      event = TestHelper.find_event(events, %{name: "/Plug/GET/fn_trace"})

      refute event[:"function.TransactionTest.HelperModule.function/1.call_count"]
    end
  end
end
