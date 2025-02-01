defmodule CollectorProtocolTest do
  use ExUnit.Case
  alias NewRelic.Harvest.Collector

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

    assert Map.has_key?(payload, :display_host)

    Jason.encode!(payload)
  end

  test "determine correct collector host" do
    assert "collector.newrelic.com" = Collector.Protocol.determine_host(nil, nil)
    assert "collector.eu01.nr-data.net" = Collector.Protocol.determine_host(nil, "eu01")
    assert "cool.newrelic.com" = Collector.Protocol.determine_host("cool.newrelic.com", nil)
  end
end
