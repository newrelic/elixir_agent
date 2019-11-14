defmodule CollectorProtocolTest do
  use ExUnit.Case
  alias NewRelic.Harvest.Collector

  test "handles invalid license key" do
    previous_logger = GenServer.call(NewRelic.Logger, {:logger, :memory})
    System.put_env("NEW_RELIC_LICENSE_KEY", "invalid_key")
    System.put_env("NEW_RELIC_HARVEST_ENABLED", "true")

    assert {:error, :license_exception} = Collector.Protocol.preconnect()

    log = GenServer.call(NewRelic.Logger, :flush)
    assert log =~ "[ERROR]"
    assert log =~ "preconnect"
    assert log =~ "NewRelic::Agent::LicenseException"
    assert log =~ "Invalid license key"

    System.delete_env("NEW_RELIC_LICENSE_KEY")
    System.delete_env("NEW_RELIC_HARVEST_ENABLED")
    GenServer.call(NewRelic.Logger, {:replace, previous_logger})
  end

  test "Connect payload" do
    [payload] = Collector.Connect.payload()

    assert get_in(payload, [:utilization, :total_ram_mib])
           |> is_integer

    assert get_in(payload, [:metadata])
           |> is_map
  end
end
