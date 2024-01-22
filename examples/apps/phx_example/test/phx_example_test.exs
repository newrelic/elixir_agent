defmodule PhxExampleTest do
  use ExUnit.Case

  alias NewRelic.Harvest.Collector

  setup_all context, do: TestSupport.simulate_agent_enabled(context)

  test "Phoenix metrics generated" do
    TestSupport.restart_harvest_cycle(Collector.Metric.HarvestCycle)
    TestSupport.restart_harvest_cycle(Collector.TransactionEvent.HarvestCycle)

    {:ok, %{body: body}} = request("/phx/bar")
    assert body =~ "Welcome to Phoenix"

    metrics = TestSupport.gather_harvest(Collector.Metric.Harvester)

    assert TestSupport.find_metric(
             metrics,
             "WebTransaction/Phoenix/PhxExampleWeb.PageController/index"
           )

    [[_, event]] = TestSupport.gather_harvest(Collector.TransactionEvent.Harvester)

    assert event[:"phoenix.endpoint"] == "PhxExampleWeb.Endpoint"
    assert event[:"phoenix.router"] == "PhxExampleWeb.Router"
    assert event[:"phoenix.controller"] == "PhxExampleWeb.PageController"
    assert event[:"phoenix.action"] == "index"
    assert event[:status] == 200
  end

  test "Phoenix metrics generated for LiveView" do
    TestSupport.restart_harvest_cycle(Collector.Metric.HarvestCycle)
    TestSupport.restart_harvest_cycle(Collector.TransactionEvent.HarvestCycle)

    {:ok, %{body: body}} = request("/phx/home")
    assert body =~ "Some content"

    metrics = TestSupport.gather_harvest(Collector.Metric.Harvester)

    assert TestSupport.find_metric(
             metrics,
             "WebTransaction/Phoenix/PhxExampleWeb.HomeLive/index"
           )

    [[_, event]] = TestSupport.gather_harvest(Collector.TransactionEvent.Harvester)

    assert event[:"phoenix.endpoint"] == "PhxExampleWeb.Endpoint"
    assert event[:"phoenix.router"] == "PhxExampleWeb.Router"
    assert event[:"phoenix.controller"] == "Phoenix.LiveView.Plug"
    assert event[:"phoenix.action"] == "index"
    assert event[:status] == 200
  end

  @tag :capture_log
  test "Phoenix error" do
    TestSupport.restart_harvest_cycle(Collector.Metric.HarvestCycle)
    TestSupport.restart_harvest_cycle(Collector.TransactionEvent.HarvestCycle)

    {:ok, %{body: body, status_code: 500}} = request("/phx/error")

    assert body =~ "Opps, Internal Server Error"

    metrics = TestSupport.gather_harvest(Collector.Metric.Harvester)

    assert TestSupport.find_metric(
             metrics,
             "WebTransaction/Phoenix/PhxExampleWeb.PageController/error"
           )

    [[_, event]] = TestSupport.gather_harvest(Collector.TransactionEvent.Harvester)

    assert event[:status] == 500
    assert event[:"phoenix.endpoint"] == "PhxExampleWeb.Endpoint"
    assert event[:"phoenix.router"] == "PhxExampleWeb.Router"
    assert event[:"phoenix.controller"] == "PhxExampleWeb.PageController"
    assert event[:"phoenix.action"] == "error"
    assert event[:error]
  end

  @tag :capture_log
  test "Phoenix LiveView error" do
    TestSupport.restart_harvest_cycle(Collector.Metric.HarvestCycle)
    TestSupport.restart_harvest_cycle(Collector.TransactionEvent.HarvestCycle)

    {:ok, %{body: body, status_code: 500}} = request("/phx/live_error")

    assert body =~ "Opps, Internal Server Error"

    metrics = TestSupport.gather_harvest(Collector.Metric.Harvester)

    assert TestSupport.find_metric(
             metrics,
             "WebTransaction/Phoenix/PhxExampleWeb.ErrorLive/index"
           )

    [[_, event]] = TestSupport.gather_harvest(Collector.TransactionEvent.Harvester)

    assert event[:status] == 500
    assert event[:"phoenix.endpoint"] == "PhxExampleWeb.Endpoint"
    assert event[:"phoenix.router"] == "PhxExampleWeb.Router"
    assert event[:"phoenix.controller"] == "Phoenix.LiveView.Plug"
    assert event[:"phoenix.action"] == "index"
    assert event[:error]
  end

  test "Phoenix route not found" do
    TestSupport.restart_harvest_cycle(Collector.Metric.HarvestCycle)
    TestSupport.restart_harvest_cycle(Collector.TransactionEvent.HarvestCycle)
    TestSupport.restart_harvest_cycle(Collector.ErrorTrace.HarvestCycle)

    {:ok, %{body: body, status_code: 404}} = request("/not_found")
    assert body =~ "Not Found"

    metrics = TestSupport.gather_harvest(Collector.Metric.Harvester)

    assert TestSupport.find_metric(
             metrics,
             "WebTransaction/Phoenix/PhxExampleWeb.Endpoint/GET"
           )

    [[_, event]] = TestSupport.gather_harvest(Collector.TransactionEvent.Harvester)

    assert event[:status] == 404
    assert event[:"phoenix.endpoint"] == "PhxExampleWeb.Endpoint"
    assert event[:"phoenix.router"] == "PhxExampleWeb.Router"
    refute event[:"phoenix.controller"]
    refute event[:error]

    errors = TestSupport.gather_harvest(Collector.ErrorTrace.Harvester)
    assert errors == []
  end

  defp request(path) do
    config = Application.get_env(:phx_example, PhxExampleWeb.Endpoint)
    NewRelic.Util.HTTP.get("http://localhost:#{config[:http][:port]}#{path}")
  end
end
