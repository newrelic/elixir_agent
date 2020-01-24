defmodule DistributedTraceTest do
  use ExUnit.Case
  use Plug.Test

  alias NewRelic.Harvest.Collector
  alias NewRelic.DistributedTrace

  @dt_header "newrelic"

  defmodule TestPlugApp do
    use Plug.Router
    use NewRelic.Transaction
    use NewRelic.Tracer

    plug(:match)
    plug(:dispatch)

    get "/" do
      [{_, outbound_payload} | _] = NewRelic.distributed_trace_headers(:http)
      send_resp(conn, 200, outbound_payload)
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

    # Transaction GUID, Trace ID initialized
    assert get_in(outbound_payload, ["d", "tx"]) |> is_binary
    assert get_in(outbound_payload, ["d", "tr"]) |> is_binary

    # Increase by 1 the priority when we generate it
    assert get_in(outbound_payload, ["d", "pr"]) > 1.0
  end

  describe "Context decoding" do
    test "ignore unknown version" do
      assert DistributedTrace.NewRelicContext.validate(%{"v" => [666]}) == :invalid
    end

    test "ignore bad base64" do
      refute DistributedTrace.NewRelicContext.decode("foobar")
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

    test "exclude id when not sampled" do
      context =
        %DistributedTrace.Context{sampled: false, span_guid: "spguid"}
        |> DistributedTrace.NewRelicContext.encode()
        |> Base.decode64!()

      refute context =~ ~s("id")
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
