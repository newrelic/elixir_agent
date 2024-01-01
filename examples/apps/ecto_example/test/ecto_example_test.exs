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
             4
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
             11
           )

    assert TestSupport.find_metric(
             metrics,
             "Datastore/allWeb",
             35
           )

    assert TestSupport.find_metric(
             metrics,
             "Datastore/all",
             35
           )
  end

  test "Table name parsing" do
    alias NewRelic.Telemetry.Ecto.Metadata

    assert {:select, "table.name"} = Metadata.parse_query(~s<SELECT * FROM table.name>)
    assert {:select, "table.name"} = Metadata.parse_query(~s<SELECT * FROM `table.name`>)
    assert {:select, "table.name"} = Metadata.parse_query(~s<SELECT * FROM [table.name]>)
    assert {:select, "table.name"} = Metadata.parse_query(~s<SELECT * FROM "table.name">)

    assert {:insert, "table"} = Metadata.parse_query(~s<INSERT INTO table VALUES 1, 2>)
    assert {:update, "table"} = Metadata.parse_query(~s<UPDATE table SET foo = bar>)
    assert {:delete, "table"} = Metadata.parse_query(~s<DELETE FROM table WHERE foo = bar>)
    assert {:create, "table"} = Metadata.parse_query(~s<CREATE TABLE table>)
    assert {:create, "table"} = Metadata.parse_query(~s<CREATE TABLE IF NOT EXISTS table>)

    assert {:select, :other} = Metadata.parse_query(~s<SELECT some_lock()>)
    assert {:select, :other} = Metadata.parse_query(~s<SELECT 1>)
    assert {:begin, :other} = Metadata.parse_query(~s<begin>)
    assert {:commit, :other} = Metadata.parse_query(~s<commit>)
    assert {:rollback, :other} = Metadata.parse_query(~s<rollback>)
  end

  defp request() do
    http_port = Application.get_env(:ecto_example, :http_port)
    NewRelic.Util.HTTP.get("http://localhost:#{http_port}/hello")
  end
end
