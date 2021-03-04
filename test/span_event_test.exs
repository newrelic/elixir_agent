defmodule SpanEventTest do
  use ExUnit.Case
  use Plug.Test

  alias NewRelic.Harvest
  alias NewRelic.DistributedTrace
  alias NewRelic.Harvest.Collector

  @dt_header "newrelic"

  setup do
    reset_agent_run = TestHelper.update(:nr_agent_run, trusted_account_key: "190")
    reset_config = TestHelper.update(:nr_config, license_key: "dummy_key", harvest_enabled: true)

    send(DistributedTrace.BackoffSampler, :reset)

    on_exit(fn ->
      reset_agent_run.()
      reset_config.()
    end)

    :ok
  end

  test "post a span event" do
    agent_run_id = Collector.AgentRun.agent_run_id()

    s1 = %NewRelic.Span.Event{
      trace_id: "abc123"
    }

    sampling = %{
      reservoir_size: 100,
      events_seen: 1
    }

    span_events = NewRelic.Span.Event.format_events([s1])

    payload = [agent_run_id, sampling, span_events]
    Collector.Protocol.span_event(payload)
  end

  test "collect and store top priority events" do
    Application.put_env(:new_relic_agent, :span_event_reservoir_size, 2)

    {:ok, harvester} =
      DynamicSupervisor.start_child(
        Collector.SpanEvent.HarvesterSupervisor,
        Collector.SpanEvent.Harvester
      )

    s1 = %NewRelic.Span.Event{priority: 3, trace_id: "abc123"}
    s2 = %NewRelic.Span.Event{priority: 2, trace_id: "def456"}
    s3 = %NewRelic.Span.Event{priority: 1, trace_id: "ghi789"}

    GenServer.cast(harvester, {:report, s1})
    GenServer.cast(harvester, {:report, s2})
    GenServer.cast(harvester, {:report, s3})

    events = GenServer.call(harvester, :gather_harvest)
    assert length(events) == 2

    assert Enum.find(events, fn [span, _, _] -> span.priority == 3 end)
    assert Enum.find(events, fn [span, _, _] -> span.priority == 2 end)
    refute Enum.find(events, fn [span, _, _] -> span.priority == 1 end)

    # Verify that the Harvester shuts down w/o error
    Process.monitor(harvester)
    Harvest.HarvestCycle.send_harvest(Collector.SpanEvent.HarvesterSupervisor, harvester)
    assert_receive {:DOWN, _ref, _, ^harvester, :shutdown}, 1000

    Application.delete_env(:new_relic_agent, :span_event_reservoir_size)
  end

  test "report a span event through the harvester" do
    TestHelper.restart_harvest_cycle(Collector.SpanEvent.HarvestCycle)

    context = %DistributedTrace.Context{sampled: true}
    mfa = {:mod, :fun, 3}

    event = %NewRelic.Span.Event{
      timestamp: System.system_time(:millisecond),
      duration: 0.120,
      name: "SomeSpan",
      category: "generic",
      category_attributes: %{}
    }

    Collector.SpanEvent.Harvester.report_span_event(event, context,
      span: {mfa, :ref},
      parent: :root
    )

    [[attrs, _, _]] = TestHelper.gather_harvest(Collector.SpanEvent.Harvester)

    assert attrs[:type] == "Span"
    assert attrs[:category] == "generic"

    TestHelper.pause_harvest_cycle(Collector.SpanEvent.HarvestCycle)
  end

  defmodule Traced do
    use NewRelic.Tracer

    @trace :hello
    def hello do
      do_hello()
    end

    @trace :do_hello
    def do_hello do
      Process.sleep(10)
      "world"
    end

    @trace :function
    def function do
      Process.sleep(10)
      NewRelic.set_span(:generic, some: "attribute")
      http_request()
    end

    @trace {:http_request, category: :external}
    def http_request do
      Process.sleep(10)
      NewRelic.set_span(:http, url: "http://example.com", method: "GET", component: "HTTPoison")
      "bar"
    end
  end

  defmodule TestPlugApp do
    use Plug.Router

    plug(:match)
    plug(:dispatch)

    get "/hello" do
      Task.async(fn ->
        Process.register(self(), :named_process)
        Process.sleep(5)
        Traced.http_request()
      end)
      |> Task.await()

      send_resp(conn, 200, Traced.hello())
    end

    get "/reset_span" do
      Traced.function()
      send_resp(conn, 200, "Yo.")
    end
  end

  test "Reset span attributes at the end" do
    TestHelper.restart_harvest_cycle(Collector.SpanEvent.HarvestCycle)

    TestHelper.request(
      TestPlugApp,
      conn(:get, "/reset_span") |> put_req_header(@dt_header, generate_inbound_payload())
    )

    span_events = TestHelper.gather_harvest(Collector.SpanEvent.Harvester)

    [function, _, _] =
      Enum.find(span_events, fn [ev, _, _] ->
        ev[:name] == "SpanEventTest.Traced.function/0"
      end)

    [http_request, _, _] =
      Enum.find(span_events, fn [ev, _, _] ->
        ev[:name] == "External/example.com/HTTPoison/GET"
      end)

    assert function[:category] == "generic"
    assert function[:some] == "attribute"
    refute function[:url]

    assert http_request[:category] == "http"
    assert http_request[:"http.url"]

    TestHelper.pause_harvest_cycle(Collector.SpanEvent.HarvestCycle)
    TestHelper.pause_harvest_cycle(Collector.TransactionEvent.HarvestCycle)
  end

  test "report span events via function tracer inside transaction inside a DT" do
    TestHelper.restart_harvest_cycle(Collector.SpanEvent.HarvestCycle)
    TestHelper.restart_harvest_cycle(Collector.TransactionEvent.HarvestCycle)

    TestHelper.request(
      TestPlugApp,
      conn(:get, "/hello") |> put_req_header(@dt_header, generate_inbound_payload())
    )

    span_events = TestHelper.gather_harvest(Collector.SpanEvent.Harvester)

    [tx_root_process_event, _, _] =
      Enum.find(span_events, fn [ev, _, _] -> ev[:"nr.entryPoint"] == true end)

    [request_process_event, _, _] =
      Enum.find(span_events, fn [ev, _, _] -> ev[:parentId] == tx_root_process_event[:guid] end)

    [function_event, _, _] =
      Enum.find(span_events, fn [ev, _, _] -> ev[:name] == "SpanEventTest.Traced.hello/0" end)

    [nested_function_event, _, _] =
      Enum.find(span_events, fn [ev, _, _] -> ev[:name] == "SpanEventTest.Traced.do_hello/0" end)

    [task_event, _, _] =
      Enum.find(span_events, fn [ev, _, _] ->
        ev[:pid] && ev[:parentId] == request_process_event[:guid]
      end)

    [nested_external_event, _, _] =
      Enum.find(span_events, fn [ev, _, _] ->
        ev[:name] == "External/example.com/HTTPoison/GET"
      end)

    [[_intrinsics, tx_event]] = TestHelper.gather_harvest(Collector.TransactionEvent.Harvester)

    assert tx_event[:parentId] == "7d3efb1b173fecfa"

    assert tx_event[:traceId] == "d6b4ba0c3a712ca"
    assert tx_root_process_event[:traceId] == "d6b4ba0c3a712ca"
    assert request_process_event[:traceId] == "d6b4ba0c3a712ca"
    assert function_event[:traceId] == "d6b4ba0c3a712ca"
    assert nested_function_event[:traceId] == "d6b4ba0c3a712ca"
    assert task_event[:traceId] == "d6b4ba0c3a712ca"
    assert nested_external_event[:traceId] == "d6b4ba0c3a712ca"

    assert tx_root_process_event[:transactionId] == tx_event[:guid]
    assert request_process_event[:transactionId] == tx_event[:guid]
    assert function_event[:transactionId] == tx_event[:guid]
    assert nested_function_event[:transactionId] == tx_event[:guid]
    assert task_event[:transactionId] == tx_event[:guid]
    assert nested_external_event[:transactionId] == tx_event[:guid]

    assert tx_event[:sampled] == true
    assert tx_root_process_event[:sampled] == true
    assert request_process_event[:sampled] == true
    assert function_event[:sampled] == true
    assert nested_function_event[:sampled] == true
    assert task_event[:sampled] == true
    assert nested_external_event[:sampled] == true

    assert tx_event[:priority] == 0.987654
    assert tx_root_process_event[:priority] == 0.987654
    assert request_process_event[:priority] == 0.987654
    assert function_event[:priority] == 0.987654
    assert nested_function_event[:priority] == 0.987654
    assert task_event[:priority] == 0.987654
    assert nested_external_event[:priority] == 0.987654

    assert function_event[:duration] > 0.009
    assert function_event[:duration] < 0.020
    assert function_event[:"tracer.reductions"] |> is_number
    assert function_event[:"tracer.reductions"] > 1

    assert tx_root_process_event[:parentId] == "5f474d64b9cc9b2a"
    assert request_process_event[:parentId] == tx_root_process_event[:guid]
    assert function_event[:parentId] == request_process_event[:guid]
    assert nested_function_event[:parentId] == function_event[:guid]
    assert task_event[:parentId] == request_process_event[:guid]
    assert nested_external_event[:parentId] == task_event[:guid]

    assert function_event[:duration] > 0
    assert task_event[:duration] > 0
    assert nested_external_event[:duration] > 0

    assert nested_external_event[:category] == "http"
    assert nested_external_event[:"http.url"] == "http://example.com"
    assert nested_external_event[:"http.method"] == "GET"
    assert nested_external_event[:"span.kind"] == "client"
    assert nested_external_event[:component] == "HTTPoison"
    assert nested_external_event[:"tracer.reductions"] |> is_number
    assert nested_external_event[:"tracer.reductions"] > 1

    assert nested_function_event[:category] == "generic"
    assert nested_function_event[:name] == "SpanEventTest.Traced.do_hello/0"
    assert nested_function_event[:"tracer.reductions"] |> is_number
    assert nested_function_event[:"tracer.reductions"] > 1

    # Ensure these will encode properly
    Jason.encode!(tx_event)
    Jason.encode!(span_events)

    TestHelper.pause_harvest_cycle(Collector.SpanEvent.HarvestCycle)
    TestHelper.pause_harvest_cycle(Collector.TransactionEvent.HarvestCycle)
  end

  describe "Generate span GUIDs" do
    test "for a process" do
      NewRelic.DistributedTrace.generate_guid(pid: self())
      NewRelic.DistributedTrace.generate_guid(pid: self(), label: {:m, :f, 1}, ref: make_ref())
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
        "sa": true,
        "pr": 0.987654
      }
    }
    """
    |> Base.encode64()
  end
end
