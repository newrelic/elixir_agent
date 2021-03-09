defmodule RedixExampleTest do
  use ExUnit.Case

  alias NewRelic.Harvest.Collector

  setup_all context, do: TestSupport.simulate_agent_enabled(context)
  setup_all context, do: TestSupport.simulate_agent_run(context)

  test "Redix queries" do
    TestSupport.restart_harvest_cycle(Collector.Metric.HarvestCycle)
    TestSupport.restart_harvest_cycle(Collector.SpanEvent.HarvestCycle)

    {:ok, %{body: body}} = request("/hello")
    assert body =~ "world"

    metrics = TestSupport.gather_harvest(Collector.Metric.Harvester)

    assert TestSupport.find_metric(
             metrics,
             "Datastore/Redis/all",
             4
           )

    assert TestSupport.find_metric(
             metrics,
             "Datastore/Redis/allWeb",
             4
           )

    assert TestSupport.find_metric(
             metrics,
             "Datastore/allWeb",
             4
           )

    assert TestSupport.find_metric(
             metrics,
             "Datastore/operation/Redis/SET",
             1
           )

    assert TestSupport.find_metric(
             metrics,
             "Datastore/operation/Redis/HSET",
             1
           )

    assert TestSupport.find_metric(
             metrics,
             {"Datastore/operation/Redis/SET", "WebTransaction/Plug/GET//hello"},
             1
           )

    span_events = TestSupport.gather_harvest(Collector.SpanEvent.Harvester)

    [get_event, _, _] =
      Enum.find(span_events, fn [ev, _, _] -> ev[:name] == "Datastore/operation/Redis/GET" end)

    assert get_event[:"peer.address"] == "localhost:6379"
    assert get_event[:"db.statement"] == "GET mykey"
    assert get_event[:"redix.connection"] =~ "PID"
    assert get_event[:"redix.connection_name"] == ":redix"

    [pipeline_event, _, _] =
      Enum.find(span_events, fn [ev, _, _] ->
        ev[:name] == "Datastore/operation/Redis/PIPELINE"
      end)

    assert pipeline_event[:"peer.address"] == "localhost:6379"

    assert pipeline_event[:"db.statement"] ==
             "DEL counter; INCR counter; INCR counter; GET counter"

    [hset_event, _, _] =
      Enum.find(span_events, fn [ev, _, _] -> ev[:name] == "Datastore/operation/Redis/HSET" end)

    assert hset_event[:"peer.address"] == "localhost:6379"
  end

  test "Redix error" do
    TestSupport.restart_harvest_cycle(Collector.SpanEvent.HarvestCycle)

    {:ok, %{body: body}} = request("/err")
    assert body =~ "bad"

    span_events = TestSupport.gather_harvest(Collector.SpanEvent.Harvester)

    [err_event, _, _] =
      Enum.find(span_events, fn [ev, _, _] ->
        ev[:name] == "Datastore/operation/Redis/PIPELINE"
      end)

    assert err_event[:"peer.address"] == "localhost:6379"
    assert err_event[:"redix.error"] == ":timeout"
  end

  defp request(path) do
    http_port = Application.get_env(:redix_example, :http_port)
    NewRelic.Util.HTTP.get("http://localhost:#{http_port}#{path}")
  end
end
