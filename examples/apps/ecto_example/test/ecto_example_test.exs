defmodule EctoExampleTest do
  use ExUnit.Case

  alias NewRelic.Harvest.Collector

  setup_all context, do: TestSupport.simulate_agent_enabled(context)

  test "Datastore metrics generated" do
    TestSupport.restart_harvest_cycle(Collector.Metric.HarvestCycle)

    {:ok, %{body: body}} = request()
    assert body =~ "world"

    metrics = TestSupport.gather_harvest(Collector.Metric.Harvester)

    assert TestSupport.find_metric(
             metrics,
             "Datastore/statement/Postgres/counts/insert",
             3
           )

    assert TestSupport.find_metric(
             metrics,
             "Datastore/statement/MySQL/counts/insert",
             3
           )

    assert TestSupport.find_metric(
             metrics,
             "Datastore/statement/SQLite3/counts/insert",
             3
           )

    assert TestSupport.find_metric(
             metrics,
             {"Datastore/statement/Postgres/counts/insert", "WebTransaction/Plug/GET//hello"},
             3
           )

    assert TestSupport.find_metric(
             metrics,
             {"Datastore/statement/MySQL/counts/insert", "WebTransaction/Plug/GET//hello"},
             3
           )

    assert TestSupport.find_metric(
             metrics,
             {"Datastore/statement/SQLite3/counts/insert", "WebTransaction/Plug/GET//hello"},
             3
           )

    assert TestSupport.find_metric(
             metrics,
             "Datastore/statement/Postgres/counts/select",
             5
           )

    assert TestSupport.find_metric(
             metrics,
             "Datastore/statement/MySQL/counts/select",
             5
           )

    assert TestSupport.find_metric(
             metrics,
             "Datastore/statement/SQLite3/counts/select",
             6
           )

    assert TestSupport.find_metric(
             metrics,
             "Datastore/statement/Postgres/counts/delete"
           )

    assert TestSupport.find_metric(
             metrics,
             "Datastore/statement/MySQL/counts/delete"
           )

    assert TestSupport.find_metric(
             metrics,
             "Datastore/statement/SQLite3/counts/delete"
           )

    assert TestSupport.find_metric(
             metrics,
             "Datastore/MySQL/allWeb",
             12
           )

    assert TestSupport.find_metric(
             metrics,
             "Datastore/Postgres/allWeb",
             12
           )

    assert TestSupport.find_metric(
             metrics,
             "Datastore/SQLite3/allWeb",
             13
           )

    assert TestSupport.find_metric(
             metrics,
             "Datastore/allWeb",
             37
           )

    assert TestSupport.find_metric(
             metrics,
             "Datastore/all",
             37
           )
  end

  defp request() do
    http_port = Application.get_env(:ecto_example, :http_port)
    NewRelic.Util.HTTP.get("http://localhost:#{http_port}/hello")
  end
end
