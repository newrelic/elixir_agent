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
    assert "collector.newrelic.com" == NewRelic.Init.determine_collector_host()

    System.put_env("NEW_RELIC_LICENSE_KEY", "eu01xeu02x37a29c3982469a3fe9999999999999")
    assert "collector.eu01.nr-data.net" == NewRelic.Init.determine_collector_host()

    System.put_env("NEW_RELIC_HOST", "cool.newrelic.com")
    assert "cool.newrelic.com" == NewRelic.Init.determine_collector_host()

    System.delete_env("NEW_RELIC_LICENSE_KEY")
    System.delete_env("NEW_RELIC_HOST")
  end
end
