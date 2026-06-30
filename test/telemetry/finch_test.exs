defmodule NewRelic.Telemetry.FinchTest do
  use ExUnit.Case
  alias NewRelic.Harvest.Collector

  defmodule TestServer do
    use Plug.Router

    plug(:match)
    plug(:dispatch)

    get "/status/:code" do
      send_resp(conn, String.to_integer(code), "")
    end

    match _ do
      send_resp(conn, 200, "")
    end
  end

  @port 8881
  @base "http://localhost:#{@port}"
  # Nothing listens here, so connecting fails - used to exercise the error path.
  @unreachable "http://localhost:1"

  setup do
    TestHelper.restart_harvest_cycle(Collector.Metric.HarvestCycle)
    TestHelper.restart_harvest_cycle(Collector.SpanEvent.HarvestCycle)
    NewRelic.DistributedTrace.BackoffSampler.reset()
    start_supervised({Finch, name: __MODULE__})
    start_supervised({Plug.Cowboy, scheme: :http, plug: TestServer, options: [port: @port]})
    :ok
  end

  test "finch external metrics" do
    request("#{@base}/200")

    metrics = TestHelper.gather_harvest(Collector.Metric.Harvester)

    assert TestHelper.find_metric(metrics, "External/localhost/Finch/GET", 1)
    assert TestHelper.find_metric(metrics, "External/localhost/all", 1)
    assert TestHelper.find_metric(metrics, "External/all", 1)
  end

  test "[:finch, :request, :stop] - 200" do
    Task.async(fn ->
      NewRelic.start_transaction("FinchTest", "200")
      request("#{@base}/status/200")
    end)
    |> Task.await()

    span_events = TestHelper.gather_harvest(Collector.SpanEvent.Harvester)

    external_span = TestHelper.find_event(span_events, "External/localhost/Finch/GET")

    assert external_span[:"http.url"] == "http://localhost/status/200"
    assert external_span[:"http.method"] == "GET"
    assert external_span[:component] == "Finch"
    assert external_span[:"response.status"] == 200
  end

  test "[:finch, :request, :stop] - 500" do
    Task.async(fn ->
      NewRelic.start_transaction("FinchTest", "500")
      request("#{@base}/status/500")
    end)
    |> Task.await()

    span_events = TestHelper.gather_harvest(Collector.SpanEvent.Harvester)

    external_span = TestHelper.find_event(span_events, "External/localhost/Finch/GET")

    assert external_span[:"http.url"] == "http://localhost/status/500"
    assert external_span[:"response.status"] == 500
  end

  test "[:finch, :request, :stop] - :error" do
    Task.async(fn ->
      NewRelic.start_transaction("FinchTest", "Error")
      request("#{@unreachable}/")
    end)
    |> Task.await()

    span_events = TestHelper.gather_harvest(Collector.SpanEvent.Harvester)

    external_span = TestHelper.find_event(span_events, "External/localhost/Finch/GET")

    assert external_span[:"http.url"] == "http://localhost/"
    assert external_span[:error] == true
    assert external_span[:"error.message"] |> is_binary()
  end

  @tag :capture_log
  test "[:finch, :request, :exception]" do
    {:ok, pid} =
      Task.start(fn ->
        NewRelic.start_transaction("FinchTest", "Exception")
        request("#{@base}/status/200", :exception)
      end)

    Process.monitor(pid)
    assert_receive {:DOWN, _ref, :process, ^pid, _reason}, 1_000

    span_events = TestHelper.gather_harvest(Collector.SpanEvent.Harvester)

    external_span = TestHelper.find_event(span_events, "External/localhost/Finch/GET")

    assert external_span[:"http.url"] == "http://localhost/status/200"
    assert external_span[:error] == true
    assert external_span[:"error.message"] =~ "Oops"
  end

  defp request(url) do
    Finch.build(:get, url)
    |> Finch.request(__MODULE__)
  end

  defp request(url, :exception) do
    Finch.build(:get, url)
    |> Finch.stream(__MODULE__, nil, fn _, _ ->
      raise "Oops"
    end)
  end
end
