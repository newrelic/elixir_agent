defmodule NewRelic.Telemetry.EctoTest do
  use ExUnit.Case

  alias NewRelic.Harvest.Collector

  defmodule TestRepo do
  end

  # Simulate an app configuring instrumentation
  @url_config [url: "ecto://postgres:password@localhost:5432/test_db"]
  setup_all do
    Application.put_env(:test_app, :ecto_repos, [__MODULE__.TestRepo])
    Application.put_env(:test_app, __MODULE__.TestRepo, @url_config)
    start_supervised({NewRelic.Telemetry.Ecto, :test_app})
    :ok
  end

  @event_name [:new_relic, :telemetry, :ecto_test, :test_repo, :query]
  @measurements %{total_time: 965_000}
  @metadata %{
    query: "SELECT i0.\"id\", i0.\"name\" FROM \"items\" AS i0",
    repo: __MODULE__.TestRepo,
    result: {:ok, %{__struct__: Postgrex.Result, command: :select}},
    source: "items",
    type: :ecto_sql_query
  }
  test "Report expected metrics based on telemetry event" do
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
