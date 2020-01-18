defmodule DistributedTraceTest do
  use ExUnit.Case
  use Plug.Test

  alias NewRelic.Harvest.Collector
  alias NewRelic.DistributedTrace

  @dt_header "newrelic"
  @w3c_traceparent "traceparent"
  @w3c_tracestate "tracestate"

  defmodule TestPlugApp do
    use Plug.Router
    use NewRelic.Transaction
    use NewRelic.Tracer

    plug(:match)
    plug(:dispatch)

    get "/" do
      [{_, outbound_payload} | _] = NewRelic.create_distributed_trace_payload(:http)
      send_resp(conn, 200, outbound_payload)
    end

    get "/w3c" do
      [_, {_, traceparent}, {_, tracestate}] = NewRelic.create_distributed_trace_payload(:http)

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
      NewRelic.create_distributed_trace_payload(:http)
    end
  end

  setup do
    prev_key = Collector.AgentRun.trusted_account_key()
    Collector.AgentRun.store(:trusted_account_key, "190")
    prev_acct = Collector.AgentRun.account_id()
    Collector.AgentRun.store(:account_id, 190)

    System.put_env("NEW_RELIC_HARVEST_ENABLED", "true")
    System.put_env("NEW_RELIC_LICENSE_KEY", "foo")
    send(DistributedTrace.BackoffSampler, :reset)

    on_exit(fn ->
      Collector.AgentRun.store(:trusted_account_key, prev_key)
      Collector.AgentRun.store(:account_id, prev_acct)
      System.delete_env("NEW_RELIC_HARVEST_ENABLED")
      System.delete_env("NEW_RELIC_LICENSE_KEY")
    end)

    :ok
  end

  test "Annotate Transaction event with DT attrs" do
    TestHelper.restart_harvest_cycle(Collector.TransactionEvent.HarvestCycle)

    TestHelper.request(
      TestPlugApp,
      conn(:get, "/")
      |> put_req_header(@dt_header, generate_inbound_payload())
    )

    [[_, attrs] | _] = TestHelper.gather_harvest(Collector.TransactionEvent.Harvester)

    assert attrs[:"parent.app"] == "2827902"
    assert attrs[:"parent.transportDuration"] >= 0.1
    assert attrs[:"parent.transportDuration"] < 1.0
    assert attrs[:parentId] == "7d3efb1b173fecfa"
    assert attrs[:parentSpanId] == "5f474d64b9cc9b2a"
    assert attrs[:traceId] == "d6b4ba0c3a712ca"

    TestHelper.pause_harvest_cycle(Collector.TransactionEvent.HarvestCycle)
  end

  test "Annotate Events with W3C attrs - incoming Mobile payload" do
    TestHelper.restart_harvest_cycle(Collector.TransactionEvent.HarvestCycle)
    TestHelper.restart_harvest_cycle(Collector.SpanEvent.HarvestCycle)

    conn(:get, "/")
    |> put_req_header(@w3c_traceparent, "00-eb970877cfd349b4dcf5eb9957283bca-5f474d64b9cc9b2a-00")
    |> put_req_header(
      @w3c_tracestate,
      "190@nr=0-2-332029-2827902-5f474d64b9cc9b2a-7d3efb1b173fecfa---1518469636035"
    )
    |> TestPlugApp.call([])

    [[_, tx_attrs] | _] = TestHelper.gather_harvest(Collector.TransactionEvent.Harvester)

    assert tx_attrs[:"parent.type"] == "Mobile"
    assert tx_attrs[:"parent.account"] == "332029"
    assert tx_attrs[:"parent.app"] == "2827902"
    assert tx_attrs[:parentId] == "7d3efb1b173fecfa"
    assert tx_attrs[:parentSpanId] == "5f474d64b9cc9b2a"
    assert tx_attrs[:traceId] == "eb970877cfd349b4dcf5eb9957283bca"

    [[span_attrs, _, _]] = TestHelper.gather_harvest(Collector.SpanEvent.Harvester)

    assert span_attrs[:traceId] == "eb970877cfd349b4dcf5eb9957283bca"
    assert span_attrs[:parentId] == "5f474d64b9cc9b2a"
    # TODO:
    # assert span_attrs[:trustedParentId] == "5f474d64b9cc9b2a"

    TestHelper.pause_harvest_cycle(Collector.TransactionEvent.HarvestCycle)
    TestHelper.pause_harvest_cycle(Collector.SpanEvent.HarvestCycle)
  end

  test "Annotate Events with W3C attrs - incoming agent payload" do
    TestHelper.restart_harvest_cycle(Collector.TransactionEvent.HarvestCycle)
    TestHelper.restart_harvest_cycle(Collector.SpanEvent.HarvestCycle)

    prev_key = Collector.AgentRun.trusted_account_key()
    Collector.AgentRun.store(:trusted_account_key, "1349956")

    conn(:get, "/")
    |> put_req_header(@w3c_traceparent, "00-74be672b84ddc4e4b28be285632bbc0a-27ddd2d8890283b4-01")
    |> put_req_header(
      @w3c_tracestate,
      "1349956@nr=0-0-1349956-41346604-27ddd2d8890283b4-b28be285632bbc0a-1-1.1273-1569367663277"
    )
    |> TestPlugApp.call([])

    [[_, tx_attrs] | _] = TestHelper.gather_harvest(Collector.TransactionEvent.Harvester)

    assert tx_attrs[:"parent.type"] == "App"
    assert tx_attrs[:"parent.account"] == "1349956"
    assert tx_attrs[:"parent.app"] == "41346604"
    assert tx_attrs[:parentId] == "b28be285632bbc0a"
    assert tx_attrs[:parentSpanId] == "27ddd2d8890283b4"
    assert tx_attrs[:sampled] == true
    assert tx_attrs[:priority] == 1.1273
    assert tx_attrs[:traceId] == "74be672b84ddc4e4b28be285632bbc0a"

    [[span_attrs, _, _]] = TestHelper.gather_harvest(Collector.SpanEvent.Harvester)

    assert span_attrs[:traceId] == "74be672b84ddc4e4b28be285632bbc0a"
    assert span_attrs[:parentId] == "27ddd2d8890283b4"
    # TODO:
    # assert span_attrs[:trustedParentId] == "27ddd2d8890283b4"

    TestHelper.pause_harvest_cycle(Collector.TransactionEvent.HarvestCycle)
    TestHelper.pause_harvest_cycle(Collector.SpanEvent.HarvestCycle)
    Collector.AgentRun.store(:trusted_account_key, prev_key)
  end

  test "Annotate Events with W3C attrs - incoming non-NR parentId payload" do
    TestHelper.restart_harvest_cycle(Collector.TransactionEvent.HarvestCycle)
    TestHelper.restart_harvest_cycle(Collector.SpanEvent.HarvestCycle)

    prev_key = Collector.AgentRun.trusted_account_key()
    Collector.AgentRun.store(:trusted_account_key, "33")

    conn(:get, "/")
    |> put_req_header(@w3c_traceparent, "00-87b1c9a429205b25e5b687d890d4821f-7d3efb1b173fecfa-00")
    |> put_req_header(
      @w3c_tracestate,
      "dd=YzRiMTIxODk1NmVmZTE4ZQ,33@nr=0-0-33-5043-27ddd2d8890283b4-5569065a5b1313bd-1-1.23456-1518469636025"
    )
    |> TestPlugApp.call([])

    [[_, tx_attrs] | _] = TestHelper.gather_harvest(Collector.TransactionEvent.Harvester)

    assert tx_attrs[:"parent.type"] == "App"
    assert tx_attrs[:"parent.account"] == "33"
    assert tx_attrs[:"parent.app"] == "5043"
    assert tx_attrs[:parentId] == "5569065a5b1313bd"
    assert tx_attrs[:parentSpanId] == "7d3efb1b173fecfa"
    assert tx_attrs[:sampled] == true
    assert tx_attrs[:priority] == 1.23456
    assert tx_attrs[:traceId] == "87b1c9a429205b25e5b687d890d4821f"

    [[span_attrs, _, _]] = TestHelper.gather_harvest(Collector.SpanEvent.Harvester)

    assert span_attrs[:traceId] == "87b1c9a429205b25e5b687d890d4821f"
    assert span_attrs[:parentId] == "7d3efb1b173fecfa"
    # TODO:
    # assert span_attrs[:trustedParentId] == "27ddd2d8890283b4"
    # assert span_attrs[:tracingVendors] == "dd"

    TestHelper.pause_harvest_cycle(Collector.TransactionEvent.HarvestCycle)
    TestHelper.pause_harvest_cycle(Collector.SpanEvent.HarvestCycle)
    Collector.AgentRun.store(:trusted_account_key, prev_key)
  end

  alias NewRelic.W3CTraceContext.{TraceParent, TraceState}

  test "Generate expected outbound payload" do
    response =
      TestHelper.request(
        TestPlugApp,
        conn(:get, "/")
        |> put_req_header(@dt_header, generate_inbound_payload())
      )

    outbound_payload =
      response.resp_body
      |> Base.decode64!()
      |> Jason.decode!()

    refute "332029" == get_in(outbound_payload, ["d", "ac"])
    refute "2827902" == get_in(outbound_payload, ["d", "ap"])
    assert "d6b4ba0c3a712ca" == get_in(outbound_payload, ["d", "tr"])
    assert true == get_in(outbound_payload, ["d", "sa"])

    # Don't change the priority when we inherit it
    assert 0.123456 = get_in(outbound_payload, ["d", "pr"])

    # ensure we delete the context after the request is complete
    refute NewRelic.DistributedTrace.Tracker.fetch(self())
  end

  test "Generate expected outbound W3C headers" do
    response =
      conn(:get, "/w3c")
      |> put_req_header(@dt_header, generate_inbound_payload())
      |> TestPlugApp.call([])

    [traceparent_header, tracestate_header] =
      response.resp_body
      |> String.split("|")

    _traceparent = TraceParent.decode(traceparent_header)

    assert traceparent_header =~ "d6b4ba0c3a712ca"

    {tracestate, _} = TraceState.decode(tracestate_header) |> TraceState.newrelic()

    assert tracestate.account_id == "190"
    # ...
  end

  test "Generate the expected metrics" do
    TestHelper.restart_harvest_cycle(Collector.Metric.HarvestCycle)

    TestHelper.request(
      TestPlugApp,
      conn(:get, "/")
      |> put_req_header(@dt_header, generate_inbound_payload())
    )

    metrics = TestHelper.gather_harvest(Collector.Metric.Harvester)

    assert TestHelper.find_metric(metrics, "DurationByCaller/Browser/190/2827902/HTTP/all")

    assert TestHelper.find_metric(
             metrics,
             "Supportability/DistributedTrace/AcceptPayload/Success"
           )

    TestHelper.pause_harvest_cycle(Collector.Metric.HarvestCycle)
  end

  test "propigate the context through connected Elixir processes" do
    response =
      TestHelper.request(
        TestPlugApp,
        conn(:get, "/connected")
        |> put_req_header(@dt_header, generate_inbound_payload())
      )

    outbound_payload =
      response.resp_body
      |> Base.decode64!()
      |> Jason.decode!()

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
      response.resp_body
      |> Base.decode64!()
      |> Jason.decode!()

    # There is no parent Transaction when we start a new Trace
    refute get_in(outbound_payload, ["d", "pa"])

    # The Transaction GUID == Trace ID because we start a new Trace
    assert get_in(outbound_payload, ["d", "tx"]) == get_in(outbound_payload, ["d", "tr"])

    # Increase by 1 the priority when we generate it
    assert get_in(outbound_payload, ["d", "pr"]) > 1.0
  end

  describe "Context decoding" do
    test "ignore unknown version" do
      assert DistributedTrace.Context.validate(%{"v" => [666]}) == :invalid
    end

    test "ignore bad base64" do
      refute DistributedTrace.Context.decode("foobar")
    end
  end

  describe "Context encoding" do
    test "exclude tk when it matches account_id" do
      context =
        %DistributedTrace.Context{account_id: "foo", trust_key: "foo"}
        |> DistributedTrace.Context.encode()
        |> Base.decode64!()

      refute context =~ "tk"
    end

    test "exclude tk when it isn't there to start" do
      context =
        %DistributedTrace.Context{account_id: "foo"}
        |> DistributedTrace.Context.encode()
        |> Base.decode64!()

      refute context =~ "tk"
    end

    test "include tk when it differs from account_id" do
      context =
        %DistributedTrace.Context{account_id: "foo", trust_key: "bar"}
        |> DistributedTrace.Context.encode()
        |> Base.decode64!()

      assert context =~ ~s("tk":"bar")
    end

    test "include id when sampled" do
      context =
        %DistributedTrace.Context{sampled: true, span_guid: "spguid"}
        |> DistributedTrace.Context.encode()
        |> Base.decode64!()

      assert context =~ ~s("id":"spguid")
    end

    test "exclude id when not sampled" do
      context =
        %DistributedTrace.Context{sampled: false, span_guid: "spguid"}
        |> DistributedTrace.Context.encode()
        |> Base.decode64!()

      refute context =~ ~s("id")
    end
  end

  describe "Context extracting" do
    test "payload TK == TAK" do
      tak = Collector.AgentRun.trusted_account_key()
      context = %DistributedTrace.Context{trust_key: tak}

      assert context == DistributedTrace.Plug.restrict_access(context)
    end

    test "payload AC == TAK" do
      tak = Collector.AgentRun.trusted_account_key()
      context = %DistributedTrace.Context{trust_key: nil, account_id: tak}

      assert context == DistributedTrace.Plug.restrict_access(context)
    end

    test "payload denied" do
      context = %DistributedTrace.Context{account_id: :FOO, trust_key: :FOO}

      assert :restricted == DistributedTrace.Plug.restrict_access(context)
    end
  end

  def generate_inbound_payload() do
    """
    {
      "v": [0,1],
      "d": {
        "ty": "Browser",
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
end
