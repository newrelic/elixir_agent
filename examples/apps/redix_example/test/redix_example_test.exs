defmodule RedixExampleTest do
  use ExUnit.Case

  alias NewRelic.Harvest.Collector

  setup_all do
    TestHelper.simulate_agent_enabled()
    TestHelper.simulate_agent_run()
  end

  test "Redix queries" do
    TestHelper.restart_harvest_cycle(Collector.Metric.HarvestCycle)
    TestHelper.restart_harvest_cycle(Collector.SpanEvent.HarvestCycle)

    {:ok, %{body: body}} = request("/hello")
    assert body =~ "world"

    metrics = TestHelper.gather_harvest(Collector.Metric.Harvester)

    assert TestHelper.find_metric(
             metrics,
             "Datastore/Redis/all",
             4
           )

    assert TestHelper.find_metric(
             metrics,
             "Datastore/Redis/allWeb",
             4
           )

    assert TestHelper.find_metric(
             metrics,
             "Datastore/allWeb",
             4
           )

    assert TestHelper.find_metric(
             metrics,
             "Datastore/operation/Redis/SET",
             1
           )

    assert TestHelper.find_metric(
             metrics,
             "Datastore/operation/Redis/HSET",
             1
           )

    assert TestHelper.find_metric(
             metrics,
             {"Datastore/operation/Redis/SET", "WebTransaction/Plug/GET//hello"},
             1
           )

    span_events = TestHelper.gather_harvest(Collector.SpanEvent.Harvester)

    [get_event, _, _] =
      Enum.find(span_events, fn [ev, _, _] -> ev[:name] == "Datastore/operation/Redis/GET" end)

    assert get_event[:"peer.address"] == "localhost:6379"
    assert get_event[:"db.statement"] == "GET mykey"
    assert get_event[:"redix.connection"] =~ "PID"
    assert get_event[:"redix.connection_name"] == ":redix"
    assert get_event[:timestamp] |> is_number
    assert get_event[:duration] > 0.0

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
    TestHelper.restart_harvest_cycle(Collector.SpanEvent.HarvestCycle)

    {:ok, %{body: body}} = request("/err")
    assert body =~ "bad"

    span_events = TestHelper.gather_harvest(Collector.SpanEvent.Harvester)

    [err_event, _, _] =
      Enum.find(span_events, fn [ev, _, _] ->
        ev[:name] == "Datastore/operation/Redis/PIPELINE"
      end)

    assert err_event[:"peer.address"] == "localhost:6379"
    # On elixir 1.14 OTP 26, the error message is "unknown POSIX error: timeout"
    # On elixir 1.12, the error message is " :timeout"
    assert err_event[:"redix.error"] =~ "timeout"
  end

  defp request(path) do
    http_port = Application.get_env(:redix_example, :http_port)
    NewRelic.Util.HTTP.get("http://localhost:#{http_port}#{path}")
  end
end
