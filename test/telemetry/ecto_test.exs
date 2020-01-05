defmodule NewRelic.Telemetry.EctoTest do
  use ExUnit.Case

  alias NewRelic.Harvest.Collector

  defmodule TestRepo do
  end

  @config [
    database: "test_db",
    username: "postgres",
    password: "password",
    hostname: "localhost",
    port: 5432
  ]
  setup_all do
    # Simulate an app configuring instrumentation
    Application.put_env(:test_app, :ecto_repos, [__MODULE__.TestRepo])
    Application.put_env(:test_app, __MODULE__.TestRepo, @config)
    start_supervised({NewRelic.Telemetry.Ecto, :test_app})
    :ok
  end

  @event_name [:new_relic, :telemetry, :ecto_test, :test_repo, :query]
  @measurements %{query_time: 965_000}
  @metadata %{
    query: "SELECT i0.\"id\", i0.\"name\" FROM \"items\" AS i0",
    repo: NewRelic.Telemetry.EctoTest.TestRepo,
    result: {:ok, %Postgrex.Result{command: :select}},
    source: "items",
    type: :ecto_sql_query
  }
  test "Report expected metrics event" do
    TestHelper.restart_harvest_cycle(Collector.Metric.HarvestCycle)

    :telemetry.execute(@event_name, @measurements, @metadata)
    :telemetry.execute(@event_name, @measurements, @metadata)
    :telemetry.execute(@event_name, @measurements, @metadata)

    metrics = TestHelper.gather_harvest(Collector.Metric.Harvester)

    assert TestHelper.find_metric(
             metrics,
             "Datastore/statement/Postgres/items/select",
             3
           )
  end
end
