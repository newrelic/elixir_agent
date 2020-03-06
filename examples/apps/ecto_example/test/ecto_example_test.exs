defmodule EctoExampleTest do
  use ExUnit.Case

  alias NewRelic.Harvest.Collector

  setup context, do: TestHelper.simulate_startup(context)

  test "Datastore metrics generated" do
    TestHelper.restart_harvest_cycle(Collector.Metric.HarvestCycle)

    {:ok, %{body: body}} = request()
    assert body =~ "world"

    metrics = TestHelper.gather_harvest(Collector.Metric.Harvester)

    assert TestHelper.find_metric(
             metrics,
             "Datastore/statement/Postgres/counts/insert",
             3
           )

    assert TestHelper.find_metric(
             metrics,
             "Datastore/statement/MySQL/counts/insert",
             3
           )

    assert TestHelper.find_metric(
             metrics,
             {"Datastore/statement/Postgres/counts/insert", "WebTransaction/Plug/GET//hello"},
             3
           )

    assert TestHelper.find_metric(
             metrics,
             {"Datastore/statement/MySQL/counts/insert", "WebTransaction/Plug/GET//hello"},
             3
           )

    assert TestHelper.find_metric(
             metrics,
             "Datastore/statement/Postgres/counts/select",
             5
           )

    assert TestHelper.find_metric(
             metrics,
             "Datastore/statement/MySQL/counts/select",
             5
           )

    assert TestHelper.find_metric(
             metrics,
             "Datastore/statement/Postgres/counts/delete"
           )

    assert TestHelper.find_metric(
             metrics,
             "Datastore/statement/MySQL/counts/delete"
           )

    assert TestHelper.find_metric(
             metrics,
             "Datastore/MySQL/allWeb",
             12
           )

    assert TestHelper.find_metric(
             metrics,
             "Datastore/Postgres/allWeb",
             12
           )

    assert TestHelper.find_metric(
             metrics,
             "Datastore/allWeb",
             24
           )
  end

  def request() do
    http_port = Application.get_env(:ecto_example, :http_port)

    {:ok, {{_, _status_code, _}, _headers, body}} =
      :httpc.request('http://localhost:#{http_port}/hello')

    {:ok, %{body: to_string(body)}}
  end
end
