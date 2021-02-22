defmodule InfiniteTracingTest do
  use ExUnit.Case
  use Plug.Test

  alias NewRelic.Harvest.TelemetrySdk
  alias NewRelic.Harvest.Collector

  setup do
    reset_agent_run = TestHelper.update(:nr_agent_run, trusted_account_key: "190")

    reset_config =
      TestHelper.update(:nr_config,
        license_key: "dummy_key",
        harvest_enabled: true,
        trace_mode: :infinite,
        automatic_attributes: %{auto: "attribute"}
      )

    on_exit(fn ->
      reset_agent_run.()
      reset_config.()
    end)

    :ok
  end

  defmodule Traced do
    use NewRelic.Tracer

    @trace :hello
    def hello do
      do_hello()
    end

    @trace :error
    def error do
      raise "Err"
    end

    @trace :exit
    def exit do
      exit(:bad)
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
        Process.sleep(5)
        Traced.http_request()
      end)
      |> Task.await()

      send_resp(conn, 200, Traced.hello())
    end

    get "/error" do
      Task.async(fn ->
        Process.sleep(5)
        Traced.error()
      end)
      |> Task.await()

      send_resp(conn, 200, "won't get here")
    end

    get "/exit" do
      Traced.exit()

      send_resp(conn, 200, "won't get here either")
    end

    get "/reset_span" do
      Traced.function()
      send_resp(conn, 200, "Yo.")
    end
  end

  @dt_header "newrelic"
  @trace_id "d6b4ba0c3a712ca"
  @parent_transaction_id "7d3efb1b173fecfa"
  @parent_span_id "5f474d64b9cc9b2a"
  def generate_inbound_payload() do
    """
    {
      "v": [0,1],
      "d": {
        "ty": "Browser",
        "ac": "190",
        "tk": "190",
        "ap": "2827902",
        "tx": "#{@parent_transaction_id}",
        "tr": "#{@trace_id}",
        "id": "#{@parent_span_id}",
        "ti": #{System.system_time(:millisecond) - 100},
        "sa": true,
        "pr": 0.987654
      }
    }
    """
    |> Base.encode64()
  end

  test "report span events via function tracer inside transaction inside a DT" do
    TestHelper.restart_harvest_cycle(TelemetrySdk.Spans.HarvestCycle)
    TestHelper.restart_harvest_cycle(Collector.TransactionEvent.HarvestCycle)

    TestHelper.request(
      TestPlugApp,
      conn(:get, "/hello") |> put_req_header(@dt_header, generate_inbound_payload())
    )

    [%{spans: spans}] = TestHelper.gather_harvest(TelemetrySdk.Spans.Harvester)

    tx_span =
      Enum.find(spans, fn %{attributes: attr} ->
        attr[:category] == "Transaction"
      end)

    tx_root_process_span =
      Enum.find(spans, fn %{attributes: attr} ->
        attr[:name] == "Transaction Root Process"
      end)

    cowboy_request_process_span =
      Enum.find(spans, fn %{attributes: attr} ->
        attr[:"parent.id"] == tx_root_process_span[:id]
      end)

    function_span =
      Enum.find(spans, fn %{attributes: attr} ->
        attr[:name] == "InfiniteTracingTest.Traced.hello/0"
      end)

    nested_function_span =
      Enum.find(spans, fn %{attributes: attr} ->
        attr[:name] == "InfiniteTracingTest.Traced.do_hello/0"
      end)

    task_span =
      Enum.find(spans, fn %{attributes: attr} ->
        attr[:name] == "Process" && attr[:"parent.id"] == cowboy_request_process_span[:id]
      end)

    nested_external_span =
      Enum.find(spans, fn %{attributes: attr} ->
        attr[:name] == "External/example.com/HTTPoison/GET"
      end)

    [[_intrinsics, tx_event]] = TestHelper.gather_harvest(Collector.TransactionEvent.Harvester)

    # Everything shares the incoming trace.id
    assert tx_event[:traceId] == @trace_id
    assert tx_span[:"trace.id"] == @trace_id
    assert tx_root_process_span[:"trace.id"] == @trace_id
    assert function_span[:"trace.id"] == @trace_id
    assert nested_function_span[:"trace.id"] == @trace_id
    assert task_span[:"trace.id"] == @trace_id
    assert nested_external_span[:"trace.id"] == @trace_id

    # We generate a "Transaction" span with the same ID as the Transaction
    assert tx_event[:guid] == tx_span[:id]

    # All spans point to the new Transaction
    assert tx_span.attributes[:transactionId] == tx_event[:guid]
    assert tx_root_process_span.attributes[:transactionId] == tx_event[:guid]
    assert function_span.attributes[:transactionId] == tx_event[:guid]
    assert nested_function_span.attributes[:transactionId] == tx_event[:guid]
    assert task_span.attributes[:transactionId] == tx_event[:guid]
    assert nested_external_span.attributes[:transactionId] == tx_event[:guid]

    # The Transaction is new, not the incoming parent Transaction
    refute tx_event[:guid] == @parent_transaction_id
    refute tx_span.attributes[:transactionId] == @parent_transaction_id

    # Only the Transaction Event's parent is the incoming parent Transaction
    assert tx_event[:parentId] == @parent_transaction_id
    refute tx_span.attributes[:"parent.id"] == @parent_transaction_id

    # The Transaction Span's parent is from the incoming parent Span
    assert tx_span.attributes[:"parent.id"] == @parent_span_id

    # The rest of the Spans parenting follows their nesting
    assert tx_root_process_span.attributes[:"parent.id"] == tx_span[:id]
    assert cowboy_request_process_span.attributes[:"parent.id"] == tx_root_process_span[:id]
    assert function_span.attributes[:"parent.id"] == cowboy_request_process_span[:id]
    assert nested_function_span.attributes[:"parent.id"] == function_span[:id]
    assert task_span.attributes[:"parent.id"] == cowboy_request_process_span[:id]
    assert nested_external_span.attributes[:"parent.id"] == task_span[:id]

    # With Infinite Tracing, we don't do sampled or priority on Spans
    refute Map.has_key?(tx_root_process_span, :sampled)
    refute Map.has_key?(function_span, :sampled)
    refute Map.has_key?(nested_function_span, :sampled)
    refute Map.has_key?(task_span, :sampled)
    refute Map.has_key?(nested_external_span, :sampled)

    refute Map.has_key?(tx_root_process_span, :priority)
    refute Map.has_key?(function_span, :priority)
    refute Map.has_key?(nested_function_span, :priority)
    refute Map.has_key?(task_span, :priority)
    refute Map.has_key?(nested_external_span, :priority)

    # But the Transaction Event still gets sampled and priority
    assert tx_event[:sampled] == true
    assert tx_event[:priority] == 0.987654

    # Other Span attributes get wired up correctly
    assert function_span.attributes[:"duration.ms"] >= 10
    assert function_span.attributes[:"duration.ms"] < 20
    assert function_span.attributes[:"tracer.reductions"] |> is_number
    assert function_span.attributes[:"tracer.reductions"] > 1

    assert task_span.attributes[:"duration.ms"] >= 15
    assert task_span.attributes[:"duration.ms"] < 25

    assert nested_external_span.attributes[:"duration.ms"] >= 10
    assert nested_external_span.attributes[:"duration.ms"] < 20
    assert nested_external_span.attributes[:category] == "http"
    assert nested_external_span.attributes[:name] == "External/example.com/HTTPoison/GET"
    assert nested_external_span.attributes[:"http.url"] == "http://example.com"
    assert nested_external_span.attributes[:"http.method"] == "GET"
    assert nested_external_span.attributes[:"span.kind"] == "client"
    assert nested_external_span.attributes[:component] == "HTTPoison"
    assert nested_external_span.attributes[:"tracer.args"] |> is_binary
    assert nested_external_span.attributes[:"tracer.reductions"] |> is_number
    assert nested_external_span.attributes[:"tracer.reductions"] > 1

    assert nested_external_span.attributes[:"tracer.function"] ==
             "InfiniteTracingTest.Traced.http_request/0"

    assert nested_function_span.attributes[:category] == "generic"
    assert nested_function_span.attributes[:name] == "InfiniteTracingTest.Traced.do_hello/0"
    assert nested_function_span.attributes[:"tracer.reductions"] |> is_number
    assert nested_function_span.attributes[:"tracer.reductions"] > 1

    # Automatic attributes assigned to the Transaction and Spansaction
    assert tx_event[:auto] == "attribute"
    assert tx_span.attributes[:auto] == "attribute"

    # Ensure these will encode properly
    Jason.encode!(tx_event)
    Jason.encode!(spans)

    TestHelper.pause_harvest_cycle(Collector.SpanEvent.HarvestCycle)
    TestHelper.pause_harvest_cycle(Collector.TransactionEvent.HarvestCycle)
  end

  @tag :capture_log
  test "error span - exception in traced span" do
    TestHelper.restart_harvest_cycle(TelemetrySdk.Spans.HarvestCycle)

    {:ok, _} = Plug.Cowboy.http(TestPlugApp, [], port: 7777)
    {:ok, {{_, 500, _}, _, _}} = :httpc.request('http://localhost:7777/error')

    [%{spans: spans}] = TestHelper.gather_harvest(TelemetrySdk.Spans.Harvester)

    error_span =
      Enum.find(spans, fn %{attributes: attr} ->
        attr[:name] == "InfiniteTracingTest.Traced.error/0"
      end)

    assert error_span.attributes[:"error.message"] == "(RuntimeError) Err"

    Plug.Cowboy.shutdown(TestPlugApp.HTTP)
    TestHelper.pause_harvest_cycle(Collector.SpanEvent.HarvestCycle)
  end

  @tag :capture_log
  test "error span - exit" do
    TestHelper.restart_harvest_cycle(TelemetrySdk.Spans.HarvestCycle)

    {:ok, _} = Plug.Cowboy.http(TestPlugApp, [], port: 7788)
    {:ok, {{_, 500, _}, _, _}} = :httpc.request('http://localhost:7788/exit')

    [%{spans: spans}] = TestHelper.gather_harvest(TelemetrySdk.Spans.Harvester)

    exit_span =
      Enum.find(spans, fn %{attributes: attr} ->
        attr[:name] == "InfiniteTracingTest.Traced.exit/0"
      end)

    assert exit_span.attributes[:"error.message"] == "(EXIT) :bad"

    Plug.Cowboy.shutdown(TestPlugApp.HTTP)
    TestHelper.pause_harvest_cycle(Collector.SpanEvent.HarvestCycle)
  end
end
