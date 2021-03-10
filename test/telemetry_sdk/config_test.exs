defmodule TelemetrySdk.ConfigTest do
  use ExUnit.Case
  alias NewRelic.Harvest.TelemetrySdk

  test "determine correct Telemetry API hosts" do
    assert %{
             log: "https://log-api.newrelic.com/log/v1",
             trace: "https://trace-api.newrelic.com/trace/v1"
           } = TelemetrySdk.Config.determine_hosts(nil, nil)

    assert %{
             log: "https://log-api.eu.newrelic.com/log/v1",
             trace: "https://trace-api.eu01.newrelic.com/trace/v1"
           } = TelemetrySdk.Config.determine_hosts(nil, "eu01")

    assert %{
             log: "https://cool-log-api.newrelic.com/log/v1",
             trace: "https://cool-trace-api.newrelic.com/trace/v1"
           } = TelemetrySdk.Config.determine_hosts("cool-collector", nil)
  end
end
