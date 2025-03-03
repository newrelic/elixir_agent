defmodule DistributedTraceTest do
  use ExUnit.Case
  use Plug.Test

  alias NewRelic.Harvest.Collector
  alias NewRelic.DistributedTrace

  @dt_header "newrelic"

  defmodule TestPlugApp do
    use Plug.Router
    use NewRelic.Tracer

    plug(:match)
    plug(:dispatch)

    get "/" do
      case NewRelic.distributed_trace_headers(:http) do
        [{_, outbound_payload} | _] -> send_resp(conn, 200, outbound_payload)
        [] -> send_resp(conn, 200, "nothin")
      end
    end

    get "/w3c" do
      [_, {_, traceparent}, {_, tracestate}] = NewRelic.distributed_trace_headers(:http)

      send_resp(conn, 200, "#{traceparent}|#{tracestate}")
    end

    get "/connected" do
      [{_, outbound_payload} | _] =
        Task.async(fn ->
          Process.sleep(20)
          external_call()
        end)
        |> Task.await()

      send_resp(conn, 200, outbound_payload)
    end

    @trace :external_call
    def external_call() do
      NewRelic.distributed_trace_headers(:http)
    end
  end

  setup do
    TestHelper.run_with(:nr_config,
      license_key: "dummy_key",
      harvest_enabled: true
    )

    TestHelper.run_with(:nr_agent_run,
      trusted_account_key: "190",
      account_id: 190,
      primary_application_id: 1441
    )

    NewRelic.DistributedTrace.BackoffSampler.reset()

    :ok
  end

  test "can disable Distributed Tracing" do
    TestHelper.run_with(:nr_features, distributed_tracing: false)
    TestHelper.restart_harvest_cycle(Collector.TransactionEvent.HarvestCycle)

    TestHelper.request(
      TestPlugApp,
      conn(:get, "/")
      |> put_req_header(@dt_header, generate_inbound_payload(:app))
    )

    events = TestHelper.gather_harvest(Collector.TransactionEvent.Harvester)
    event = TestHelper.find_event(events, "WebTransaction/Plug/GET")

    assert event[:name]
    refute event[:error_reason]

    refute event[:"parent.app"]
    refute event[:parentId]
    refute event[:parentSpanId]
    refute event[:traceId]

    TestHelper.pause_harvest_cycle(Collector.TransactionEvent.HarvestCycle)
  end

  test "Annotate Transaction event with DT attrs" do
    TestHelper.restart_harvest_cycle(Collector.TransactionEvent.HarvestCycle)

    TestHelper.request(
      TestPlugApp,
      conn(:get, "/")
      |> put_req_header(@dt_header, generate_inbound_payload(:app))
    )

    events = TestHelper.gather_harvest(Collector.TransactionEvent.Harvester)
    event = TestHelper.find_event(events, "WebTransaction/Plug/GET")

    assert event[:"parent.app"] == "2827902"
    assert is_number(event[:"parent.transportDuration"])
    assert event[:parentId] == "7d3efb1b173fecfa"
    assert event[:parentSpanId] == "5f474d64b9cc9b2a"
    assert event[:traceId] == "d6b4ba0c3a712ca"

    TestHelper.pause_harvest_cycle(Collector.TransactionEvent.HarvestCycle)
  end

  test "Generate linkage from a Browser app" do
    TestHelper.restart_harvest_cycle(Collector.TransactionEvent.HarvestCycle)

    response =
      TestHelper.request(
        TestPlugApp,
        conn(:get, "/")
        |> put_req_header(@dt_header, generate_inbound_payload(:browser))
      )

    outbound_payload =
      response.body
      |> Base.decode64!()
      |> NewRelic.JSON.decode!()

    assert get_in(outbound_payload, ["d", "tr"]) == "d6b4ba0c3a712ca"
    assert get_in(outbound_payload, ["d", "ac"]) == "190"
    assert get_in(outbound_payload, ["d", "ap"]) == "1441"

    events = TestHelper.gather_harvest(Collector.TransactionEvent.Harvester)
    event = TestHelper.find_event(events, "WebTransaction/Plug/GET")

    assert event[:traceId] == "d6b4ba0c3a712ca"
    assert event[:"parent.app"] == "2827902"
    assert event[:"parent.type"] == "Browser"
    assert event[:parentSpanId] == "5f474d64b9cc9b2a"
    refute event[:parentId]
  end

  test "Generate the expected metrics" do
    TestHelper.restart_harvest_cycle(Collector.Metric.HarvestCycle)

    TestHelper.request(
      TestPlugApp,
      conn(:get, "/")
      |> put_req_header(@dt_header, generate_inbound_payload(:app))
    )

    metrics = TestHelper.gather_harvest(Collector.Metric.Harvester)

    assert TestHelper.find_metric(metrics, "DurationByCaller/App/190/2827902/HTTP/all")

    assert TestHelper.find_metric(
             metrics,
             "Supportability/DistributedTrace/AcceptPayload/Success"
           )

    TestHelper.pause_harvest_cycle(Collector.Metric.HarvestCycle)
  end

  test "propagate the context through connected Elixir processes" do
    response =
      TestHelper.request(
        TestPlugApp,
        conn(:get, "/connected")
        |> put_req_header(@dt_header, generate_inbound_payload(:app))
      )

    outbound_payload =
      response.body
      |> Base.decode64!()
      |> NewRelic.JSON.decode!()

    data = outbound_payload["d"]
    assert "d6b4ba0c3a712ca" == data["tr"]

    mfa_segment =
      NewRelic.DistributedTrace.encode_guid({DistributedTraceTest.TestPlugApp, :external_call, 0})

    # ensure that outgoing "id" (Span GUID) is correct
    assert String.contains?(data["id"], mfa_segment)
  end

  test "generate an outgoing payload when there is no incoming one" do
    response = TestHelper.request(TestPlugApp, conn(:get, "/"))

    outbound_payload =
      response.body
      |> Base.decode64!()
      |> NewRelic.JSON.decode!()

    # Span GUID, Transaction ID, Trace ID initialized
    assert get_in(outbound_payload, ["d", "id"]) |> is_binary
    assert get_in(outbound_payload, ["d", "tx"]) |> is_binary
    assert get_in(outbound_payload, ["d", "tr"]) |> is_binary

    # Increase by 1 the priority when we generate it
    assert get_in(outbound_payload, ["d", "pr"]) > 1.0
  end

  test "asking for DT context when there is none" do
    headers = NewRelic.DistributedTrace.distributed_trace_headers(:http)
    assert length(headers) == 0

    Task.async(fn ->
      NewRelic.start_transaction("TransactionCategory", "MyTaskName")

      headers = NewRelic.DistributedTrace.distributed_trace_headers(:http)
      assert length(headers) > 0
    end)
    |> Task.await()
  end

  test "Start an Other transaction with inbound DT headers" do
    headers = %{@dt_header => generate_inbound_payload(:browser)}

    Task.async(fn ->
      NewRelic.start_transaction("Category", "Name", headers)

      headers = NewRelic.distributed_trace_headers(:other)

      context = DistributedTrace.NewRelicContext.decode(Map.get(headers, @dt_header))

      assert context.trace_id == "d6b4ba0c3a712ca"
    end)
    |> Task.await()
  end

  describe "Context decoding" do
    test "ignore unknown version" do
      payload = %{"v" => [666]} |> NewRelic.JSON.encode!() |> Base.encode64()

      assert DistributedTrace.NewRelicContext.decode(payload) == :bad_dt_payload
    end

    test "ignore bad base64" do
      assert DistributedTrace.NewRelicContext.decode("foobar") == :bad_dt_payload
    end
  end

  describe "Context encoding" do
    test "exclude tk when it matches account_id" do
      context =
        %DistributedTrace.Context{account_id: "foo", sampled: true, trust_key: "foo"}
        |> DistributedTrace.NewRelicContext.encode()
        |> Base.decode64!()

      refute context =~ "tk"
    end

    test "exclude tk when it isn't there to start" do
      context =
        %DistributedTrace.Context{account_id: "foo", sampled: true}
        |> DistributedTrace.NewRelicContext.encode()
        |> Base.decode64!()

      refute context =~ "tk"
    end

    test "include tk when it differs from account_id" do
      context =
        %DistributedTrace.Context{account_id: "foo", sampled: true, trust_key: "bar"}
        |> DistributedTrace.NewRelicContext.encode()
        |> Base.decode64!()

      assert context =~ ~s("tk":"bar")
    end

    test "include id when sampled" do
      context =
        %DistributedTrace.Context{sampled: true, span_guid: "spguid"}
        |> DistributedTrace.NewRelicContext.encode()
        |> Base.decode64!()

      assert context =~ ~s("id":"spguid")
    end

    test "include id when not sampled" do
      context =
        %DistributedTrace.Context{sampled: false, span_guid: "spguid"}
        |> DistributedTrace.NewRelicContext.encode()
        |> Base.decode64!()

      assert context =~ ~s("id":"spguid")
    end
  end

  describe "Context extracting" do
    test "payload TK == TAK" do
      tak = Collector.AgentRun.trusted_account_key()
      context = %DistributedTrace.Context{trust_key: tak}

      assert context == DistributedTrace.NewRelicContext.restrict_access(context)
    end

    test "payload AC == TAK" do
      tak = Collector.AgentRun.trusted_account_key()
      context = %DistributedTrace.Context{trust_key: nil, account_id: tak}

      assert context == DistributedTrace.NewRelicContext.restrict_access(context)
    end

    test "payload denied" do
      context = %DistributedTrace.Context{account_id: :FOO, trust_key: :FOO}

      assert :restricted == DistributedTrace.NewRelicContext.restrict_access(context)
    end

    test "payload is invalid" do
      assert :bad_dt_payload == DistributedTrace.NewRelicContext.restrict_access(:bad_dt_payload)
    end
  end

  test "correctly handle a bad NR payload" do
    response =
      TestHelper.request(
        TestPlugApp,
        put_req_header(conn(:get, "/"), @dt_header, "asdf")
      )

    assert response.status_code == 200
  end

  test "correctly handle a NR payload in an unknown version" do
    payload =
      """
      {
        "v": [0, 2],
        "d": {
          "d.ac": "2497233",
          "d.ap": "488951130",
          "d.id": "8e81319f548742aa",
          "d.ti": 1640202478572,
          "d.tr": "b4799f25a31049eebc2f808732b28e35",
          "d.ty": "Mobile"
        }
      }
      """
      |> Base.encode64()

    response =
      TestHelper.request(
        TestPlugApp,
        put_req_header(conn(:get, "/"), @dt_header, payload)
      )

    assert response.status_code == 200
  end

  test "Always handle payload w/o sampling decision" do
    payload =
      """
      {
        "v":[0,1],
        "d":{
          "ty": "Browser",
          "ac":"190",
          "tk": "190",
          "ap":"234567890",
          "id":"123ab456cd78e9f0",
          "tr":"234b56cd789e0fa1",
          "ti":1581385629189
        }
      }
      """
      |> Base.encode64()

    response =
      TestHelper.request(
        TestPlugApp,
        conn(:get, "/w3c")
        |> put_req_header(@dt_header, payload)
      )

    [traceparent_header, tracestate_header] =
      response.body
      |> String.split("|")

    assert traceparent_header |> is_binary
    assert tracestate_header |> is_binary
  end

  def generate_inbound_payload(:app) do
    """
    {
      "v": [0,1],
      "d": {
        "ty": "App",
        "ac": "190",
        "tk": "190",
        "ap": "2827902",
        "tx": "7d3efb1b173fecfa",
        "tr": "d6b4ba0c3a712ca",
        "id": "5f474d64b9cc9b2a",
        "ti": #{System.system_time(:millisecond) - 100},
        "pr": 0.123456,
        "sa": true
      }
    }
    """
    |> Base.encode64()
  end

  def generate_inbound_payload(:browser) do
    """
    {
      "v": [0,1],
      "d": {
        "ty": "Browser",
        "ac": "190",
        "ap": "2827902",
        "tr": "d6b4ba0c3a712ca",
        "id": "5f474d64b9cc9b2a",
        "ti": #{System.system_time(:millisecond) - 100}
      }
    }
    """
    |> Base.encode64()
  end
end
