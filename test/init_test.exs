defmodule InitTest do
  use ExUnit.Case

  test "check for region prefix in license_key" do
    refute NewRelic.Init.determine_region("08a2ad66c637a29c3982469a3fe9999999999999")

    assert "eu01" == NewRelic.Init.determine_region("eu01xx66c637a29c3982469a3fe9999999999999")
    assert "gov01" == NewRelic.Init.determine_region("gov01x66c637a29c3982469a3fe9999999999999")
    assert "foo1234" == NewRelic.Init.determine_region("foo1234xc637a29c3982469a3fe9999999999999")
    assert "20foo" == NewRelic.Init.determine_region("20foox66c637a29c3982469a3fe9999999999999")
    assert "eu01" == NewRelic.Init.determine_region("eu01xeu02x37a29c3982469a3fe9999999999999")
  end

  test "set correct collector host" do
    assert {"collector.newrelic.com", _} = NewRelic.Init.determine_collector_host(nil, nil)

    assert {"collector.eu01.nr-data.net", _} =
             NewRelic.Init.determine_collector_host(
               nil,
               "eu01xeu02x37a29c3982469a3fe9999999999999"
             )

    assert {"cool.newrelic.com", _} =
             NewRelic.Init.determine_collector_host("cool.newrelic.com", nil)
  end
end
