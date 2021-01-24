defmodule CollectorProtocolTest do
  use ExUnit.Case
  alias NewRelic.Harvest.Collector

  test "handles invalid license key" do
    previous_logger = GenServer.call(NewRelic.Logger, {:logger, :memory})

    reset_config =
      TestHelper.update(:nr_config, license_key: "invalid_key", harvest_enabled: true)

    assert {:error, :force_disconnect} = Collector.Protocol.preconnect()

    log = GenServer.call(NewRelic.Logger, :flush)
    assert log =~ "[ERROR]"
    assert log =~ "preconnect"
    assert log =~ "NewRelic::Agent::LicenseException"
    assert log =~ "Invalid license key"

    reset_config.()
    GenServer.call(NewRelic.Logger, {:replace, previous_logger})
  end

  test "Connect payload" do
    [payload] = Collector.Connect.payload()

    assert get_in(payload, [:utilization, :total_ram_mib])
           |> is_integer

    assert get_in(payload, [:metadata])
           |> is_map

    assert get_in(payload, [:environment])
           |> Enum.find(&match?(["OTP Version", _], &1))

    assert get_in(payload, [:environment])
           |> Enum.find(&match?(["ERTS Version", _], &1))

    Jason.encode!(payload)
  end
end
