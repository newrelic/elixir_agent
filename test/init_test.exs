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

  test "handle config default properly" do
    on_exit(fn ->
      Application.delete_env(:new_relic_agent, :harvest_enabled)
      System.delete_env("NEW_RELIC_HARVEST_ENABLED")
      NewRelic.Init.init_config()
    end)

    Application.put_env(:new_relic_agent, :harvest_enabled, true)
    NewRelic.Init.init_config()
    assert NewRelic.Config.get(:harvest_enabled)

    Application.put_env(:new_relic_agent, :harvest_enabled, false)
    NewRelic.Init.init_config()
    refute NewRelic.Config.get(:harvest_enabled)

    System.put_env("NEW_RELIC_HARVEST_ENABLED", "true")
    NewRelic.Init.init_config()
    assert NewRelic.Config.get(:harvest_enabled)

    System.put_env("NEW_RELIC_HARVEST_ENABLED", "false")
    NewRelic.Init.init_config()
    refute NewRelic.Config.get(:harvest_enabled)
  end
end
