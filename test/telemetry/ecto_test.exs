defmodule NewRelic.Telemetry.EctoTest do
  use ExUnit.Case

  alias NewRelic.Harvest.Collector

  defmodule TestRepo do
  end

  # Simulate detection of an Ecto Repo
  setup_all do
    start_supervised(
      {NewRelic.Telemetry.Ecto,
       [
         repo: __MODULE__.TestRepo,
         opts: [telemetry_prefix: [:new_relic_ecto_test]]
       ]}
    )

    :ok
  end

  @event_name [:new_relic_ecto_test, :query]
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
