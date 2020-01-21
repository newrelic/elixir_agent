defmodule W3CTraceContextTest do
  use ExUnit.Case
  use Plug.Test

  alias NewRelic.W3CTraceContext.TraceParent
  alias NewRelic.W3CTraceContext.TraceState

  alias NewRelic.Harvest.Collector
  alias NewRelic.DistributedTrace

  @w3c_traceparent "traceparent"
  @w3c_tracestate "tracestate"

  defmodule TestPlugApp do
    use Plug.Router
    use NewRelic.Transaction

    plug(:match)
    plug(:dispatch)

    get "/w3c" do
      [_, {_, traceparent}, {_, tracestate}] = NewRelic.create_distributed_trace_payload(:http)
      send_resp(conn, 200, "#{traceparent}|#{tracestate}")
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

  test "TraceParent parsing" do
    assert_invalid(TraceParent, "00-00000000000000000000000000000000-aaaaaaaaaaaaaaaa-01")
    assert_invalid(TraceParent, "00-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-0000000000000000-01")

    assert_invalid(TraceParent, ".0-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-aaaaaaaaaaaaaaaa-01")
    assert_invalid(TraceParent, "00-aaaaaaaaaaaaaaaaaaa.aaaaaaaaaaaa-aaaaaaaaaaaaaaaa-01")
    assert_invalid(TraceParent, "00-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-aaaaaa.aaaaaaaaa-01")
    assert_invalid(TraceParent, "00-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-aaaaaaaaaaaaaaaa-.1")

    assert_invalid(TraceParent, "asdf")

    assert_valid(TraceParent, "00-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-aaaaaaaaaaaaaaaa-01")
    assert_valid(TraceParent, "00-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-aaaaaaaaaaaaaaaa-00")
  end

  test "TraceState parsing" do
    assert %{members: []} = TraceState.decode([""])
    assert %{members: []} = TraceState.decode([" "])

    # Don't allow duplicates
    assert %{members: []} = TraceState.decode(["foo=bar,foo=baz"])

    # Invalid format
    assert %{members: []} = TraceState.decode(["foo=bar=baz"])
    assert %{members: []} = TraceState.decode(["foo=,bar=3"])
    assert %{members: []} = TraceState.decode(["foo@bar@baz=1,bar=2"])
    assert %{members: []} = TraceState.decode(["foo@=1,bar=2"])
    assert %{members: []} = TraceState.decode(["foo =1"])
    assert %{members: []} = TraceState.decode(["foo.bar=1"])

    # Optional white space
    assert %{members: [%{key: "foo"}, %{key: "bar"}]} = TraceState.decode(["foo=1 , bar=2"])

    assert_valid(
      TraceState,
      "190@nr=0-0-709288-8599547-f85f42fd82a4cf1d-164d3b4b0d09cb05-1-0.789-1563574856827,foo@vendor=value"
    )
  end

  test "header extraction & re-generation" do
    traceparent = "00-74be672b84ddc4e4b28be285632bbc0a-27ddd2d8890283b4-01"

    tracestate =
      "190@nr=0-0-1349956-41346604-27ddd2d8890283b4-b28be285632bbc0a-1-1.1273-1569367663277,foo@vendor=value"

    tracestate_no_time = "190@nr=0-0-1349956-41346604-27ddd2d8890283b4-b28be285632bbc0a-1-1.1273-"
    tracestate_other_vendor = ",foo@vendor=value"

    conn =
      Plug.Test.conn(:get, "/w3c")
      |> Plug.Conn.put_req_header("traceparent", traceparent)
      |> Plug.Conn.put_req_header("tracestate", tracestate)

    context = NewRelic.W3CTraceContext.extract(conn)

    {new_traceparent, new_tracestate} = NewRelic.W3CTraceContext.generate(context)

    assert new_traceparent == traceparent
    assert new_tracestate =~ tracestate_no_time
    assert new_tracestate =~ tracestate_other_vendor
  end

  def assert_valid(module, header) do
    assert String.downcase(header) ==
             [header]
             |> module.decode()
             |> module.encode()
  end

  def assert_invalid(module, header) do
    assert :invalid == module.decode(header)
  end

  test "Annotate Events with W3C attrs - incoming Mobile payload" do
    TestHelper.restart_harvest_cycle(Collector.TransactionEvent.HarvestCycle)
    TestHelper.restart_harvest_cycle(Collector.SpanEvent.HarvestCycle)

    conn(:get, "/w3c")
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
    assert span_attrs[:trustedParentId] == "5f474d64b9cc9b2a"

    TestHelper.pause_harvest_cycle(Collector.TransactionEvent.HarvestCycle)
    TestHelper.pause_harvest_cycle(Collector.SpanEvent.HarvestCycle)
  end

  test "Annotate Events with W3C attrs - incoming agent payload" do
    TestHelper.restart_harvest_cycle(Collector.TransactionEvent.HarvestCycle)
    TestHelper.restart_harvest_cycle(Collector.SpanEvent.HarvestCycle)

    prev_key = Collector.AgentRun.trusted_account_key()
    Collector.AgentRun.store(:trusted_account_key, "1349956")

    conn(:get, "/w3c")
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
    assert span_attrs[:trustedParentId] == "27ddd2d8890283b4"
    refute span_attrs[:tracingVendors]

    TestHelper.pause_harvest_cycle(Collector.TransactionEvent.HarvestCycle)
    TestHelper.pause_harvest_cycle(Collector.SpanEvent.HarvestCycle)
    Collector.AgentRun.store(:trusted_account_key, prev_key)
  end

  test "Annotate Events with W3C attrs - incoming non-NR tracestate" do
    TestHelper.restart_harvest_cycle(Collector.TransactionEvent.HarvestCycle)
    TestHelper.restart_harvest_cycle(Collector.SpanEvent.HarvestCycle)

    prev_key = Collector.AgentRun.trusted_account_key()

    conn(:get, "/w3c")
    |> put_req_header(@w3c_traceparent, "00-74be672b84ddc4e4b28be285632bbc0a-27ddd2d8890283b4-01")
    |> put_req_header(@w3c_tracestate, "vendor=value")
    |> TestPlugApp.call([])

    [[_, tx_attrs] | _] = TestHelper.gather_harvest(Collector.TransactionEvent.Harvester)

    refute tx_attrs[:"parent.account"]
    refute tx_attrs[:"parent.app"]

    assert tx_attrs[:parentSpanId] == "27ddd2d8890283b4"
    assert tx_attrs[:traceId] == "74be672b84ddc4e4b28be285632bbc0a"

    [[span_attrs, _, _]] = TestHelper.gather_harvest(Collector.SpanEvent.Harvester)

    assert span_attrs[:traceId] == "74be672b84ddc4e4b28be285632bbc0a"
    assert span_attrs[:parentId] == "27ddd2d8890283b4"

    TestHelper.pause_harvest_cycle(Collector.TransactionEvent.HarvestCycle)
    TestHelper.pause_harvest_cycle(Collector.SpanEvent.HarvestCycle)
    Collector.AgentRun.store(:trusted_account_key, prev_key)
  end

  test "Annotate Events with W3C attrs - incoming non-NR parentId payload" do
    TestHelper.restart_harvest_cycle(Collector.TransactionEvent.HarvestCycle)
    TestHelper.restart_harvest_cycle(Collector.SpanEvent.HarvestCycle)

    prev_key = Collector.AgentRun.trusted_account_key()
    Collector.AgentRun.store(:trusted_account_key, "33")

    conn(:get, "/w3c")
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
    assert span_attrs[:trustedParentId] == "27ddd2d8890283b4"
    assert span_attrs[:tracingVendors] == "dd"

    TestHelper.pause_harvest_cycle(Collector.TransactionEvent.HarvestCycle)
    TestHelper.pause_harvest_cycle(Collector.SpanEvent.HarvestCycle)
    Collector.AgentRun.store(:trusted_account_key, prev_key)
  end

  alias NewRelic.W3CTraceContext.{TraceParent, TraceState}

  test "Generate expected outbound W3C headers" do
    prev_acct = Collector.AgentRun.account_id()
    Collector.AgentRun.store(:account_id, 3482)
    prev_app = Collector.AgentRun.primary_application_id()
    Collector.AgentRun.store(:primary_application_id, 53442)

    response =
      conn(:get, "/w3c")
      |> put_req_header(
        @w3c_traceparent,
        "00-74be672b84ddc4e4b28be285632bbc0a-d6e4e06002e24189-01"
      )
      |> put_req_header(
        @w3c_tracestate,
        "190@nr=0-0-212311-51424-d6e4e06002e24189-27856f70d3d314b7-1-0.421-1482959525577"
      )
      |> TestPlugApp.call([])

    [traceparent_header, tracestate_header] =
      response.resp_body
      |> String.split("|")

    expected_traceparent = ~r/00-74be672b84ddc4e4b28be285632bbc0a-\w{16}-01/
    expected_tracestate = ~r/190@nr=0-0-3482-53442-\w{16}-\w{16}-1-0.421-\d{13}/

    assert tracestate_header =~ expected_tracestate
    assert traceparent_header =~ expected_traceparent

    Collector.AgentRun.store(:account_id, prev_acct)
    Collector.AgentRun.store(:primary_application_id, prev_app)
  end

  test "Generate expected outbound W3C headers - no tracestate" do
    prev_acct = Collector.AgentRun.account_id()
    Collector.AgentRun.store(:account_id, 3482)
    prev_app = Collector.AgentRun.primary_application_id()
    Collector.AgentRun.store(:primary_application_id, 53442)

    response =
      conn(:get, "/w3c")
      |> put_req_header(
        @w3c_traceparent,
        "00-74be672b84ddc4e4b28be285632bbc0a-d6e4e06002e24189-01"
      )
      |> TestPlugApp.call([])

    [traceparent_header, tracestate_header] =
      response.resp_body
      |> String.split("|")

    expected_traceparent = ~r/00-74be672b84ddc4e4b28be285632bbc0a-\w{16}-01/
    expected_tracestate = ~r/190@nr=0-0-3482-53442-\w{16}-\w{16}/

    assert tracestate_header =~ expected_tracestate
    assert traceparent_header =~ expected_traceparent

    Collector.AgentRun.store(:account_id, prev_acct)
    Collector.AgentRun.store(:primary_application_id, prev_app)
  end

  test "Generate expected outbound W3C headers - bad traceparent" do
    response =
      conn(:get, "/w3c")
      |> put_req_header(
        @w3c_traceparent,
        "00-74be672b84ddc.....8be285632bbc0a-d6e4e06002e24189-01"
      )
      |> TestPlugApp.call([])

    [traceparent_header, _tracestate_header] =
      response.resp_body
      |> String.split("|")

    # Create a new Trace ID
    refute traceparent_header =~ "74be672b84ddc.....8be285632bbc0a"
  end

  test "Generate expected outbound W3C headers - future version" do
    response =
      conn(:get, "/w3c")
      |> put_req_header(
        @w3c_traceparent,
        "cc-74be672b84ddc4e4b28be285632bbc0a-d6e4e06002e24189-01-future-stuff"
      )
      |> TestPlugApp.call([])

    [traceparent_header, _tracestate_header] =
      response.resp_body
      |> String.split("|")

    # Accept the Trace ID
    assert traceparent_header =~ ~r/00-74be672b84ddc4e4b28be285632bbc0a-\w{16}-01/
  end
end
