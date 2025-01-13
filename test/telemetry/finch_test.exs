defmodule NewRelic.Telemetry.FinchTest do
  use ExUnit.Case
  alias NewRelic.Harvest.Collector

  setup do
    TestHelper.restart_harvest_cycle(Collector.Metric.HarvestCycle)
    TestHelper.restart_harvest_cycle(Collector.SpanEvent.HarvestCycle)
    send(NewRelic.DistributedTrace.BackoffSampler, :reset)

    start_supervised({Finch, name: __MODULE__})

    on_exit(fn ->
      TestHelper.pause_harvest_cycle(Collector.Metric.HarvestCycle)
      TestHelper.pause_harvest_cycle(Collector.SpanEvent.HarvestCycle)
    end)
  end

  test "finch external metrics" do
    request("https://httpstat.us/200")

    metrics = TestHelper.gather_harvest(Collector.Metric.Harvester)

    assert TestHelper.find_metric(metrics, "External/httpstat.us/Finch/GET", 1)
    assert TestHelper.find_metric(metrics, "External/httpstat.us/all", 1)
    assert TestHelper.find_metric(metrics, "External/all", 1)
  end

  test "[:finch, :request, :stop] - 200" do
    Task.async(fn ->
      NewRelic.start_transaction("FinchTest", "200")
      request("https://httpstat.us/200")
    end)
    |> Task.await()

    span_events = TestHelper.gather_harvest(Collector.SpanEvent.Harvester)

    external_span = TestHelper.find_span(span_events, "External/httpstat.us/Finch/GET")

    assert external_span[:"request.url"] == "https://httpstat.us/200"
    assert external_span[:"response.status"] == 200
  end

  test "[:finch, :request, :stop] - 500" do
    Task.async(fn ->
      NewRelic.start_transaction("FinchTest", "500")
      request("https://httpstat.us/500")
    end)
    |> Task.await()

    span_events = TestHelper.gather_harvest(Collector.SpanEvent.Harvester)

    external_span = TestHelper.find_span(span_events, "External/httpstat.us/Finch/GET")

    assert external_span[:"request.url"] == "https://httpstat.us/500"
    assert external_span[:"response.status"] == 500
  end

  test "[:finch, :request, :stop] - :error" do
    Task.async(fn ->
      NewRelic.start_transaction("FinchTest", "Error")
      request("https://nxdomain")
    end)
    |> Task.await()

    span_events = TestHelper.gather_harvest(Collector.SpanEvent.Harvester)

    external_span = TestHelper.find_span(span_events, "External/nxdomain/Finch/GET")

    assert external_span[:"request.url"] == "https://nxdomain/"
    assert external_span[:error] == true
    assert external_span[:"error.message"] |> is_binary()
  end

  @tag :capture_log
  test "[:finch, :request, :exception]" do
    {:ok, pid} =
      Task.start(fn ->
        NewRelic.start_transaction("FinchTest", "Exception")
        request("https://httpstat.us/200", :exception)
      end)

    Process.monitor(pid)
    assert_receive {:DOWN, _ref, :process, ^pid, _reason}, 1_000

    span_events = TestHelper.gather_harvest(Collector.SpanEvent.Harvester)

    external_span = TestHelper.find_span(span_events, "External/httpstat.us/Finch/GET")

    assert external_span[:"request.url"] == "https://httpstat.us/200"
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
