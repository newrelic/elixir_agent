defmodule PhxExampleTest do
  use ExUnit.Case

  alias NewRelic.Harvest.Collector

  setup_all do
    # Simulate the agent fully starting up
    Process.whereis(Collector.TaskSupervisor) ||
      NewRelic.EnabledSupervisor.start_link(:ok)

    :ok
  end

  test "Phoenix metrics generated" do
    TestHelper.restart_harvest_cycle(Collector.Metric.HarvestCycle)
    TestHelper.restart_harvest_cycle(Collector.TransactionEvent.HarvestCycle)

    {:ok, %{body: body}} = request("/phx/bar")
    assert body =~ "Welcome to Phoenix"

    metrics = TestHelper.gather_harvest(Collector.Metric.Harvester)

    assert TestHelper.find_metric(
             metrics,
             "WebTransaction/Phoenix/GET//phx/:foo"
           )

    [[_, event]] = TestHelper.gather_harvest(Collector.TransactionEvent.Harvester)

    assert event[:"phoenix.endpoint"] == "PhxExampleWeb.Endpoint"
    assert event[:"phoenix.router"] == "PhxExampleWeb.Router"
    assert event[:"phoenix.controller"] == "PhxExampleWeb.PageController"
    assert event[:"phoenix.action"] == "index"
    assert event[:status] == 200
  end

  test "Phoenix error" do
    TestHelper.restart_harvest_cycle(Collector.TransactionEvent.HarvestCycle)

    {:ok, %{body: body, status_code: 500}} = request("/phx/error")
    assert body =~ "Internal Server Error"

    [[_, event]] = TestHelper.gather_harvest(Collector.TransactionEvent.Harvester)

    assert event[:status] == 500
    assert event[:"phoenix.endpoint"] == "PhxExampleWeb.Endpoint"
    assert event[:"phoenix.router"] == "PhxExampleWeb.Router"
    assert event[:"phoenix.controller"] == "PhxExampleWeb.PageController"
    assert event[:"phoenix.action"] == "error"
    assert event[:error]
  end

  test "Phoenix route not found" do
    TestHelper.restart_harvest_cycle(Collector.TransactionEvent.HarvestCycle)

    {:ok, %{body: body, status_code: 404}} = request("/not_found")
    assert body =~ "Not Found"

    [[_, event]] = TestHelper.gather_harvest(Collector.TransactionEvent.Harvester)

    assert event[:status] == 404
    refute event[:"phoenix.controller"]
    refute event[:error]
  end

  def request(path) do
    config = Application.get_env(:phx_example, PhxExampleWeb.Endpoint)

    {:ok, {{_, status_code, _}, _headers, body}} =
      :httpc.request('http://localhost:#{config[:http][:port]}#{path}')

    {:ok, %{body: to_string(body), status_code: status_code}}
  end
end
