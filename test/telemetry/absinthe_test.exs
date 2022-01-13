defmodule NewRelic.Telemetry.AbsintheTest do
  use ExUnit.Case, async: true
  alias NewRelic.Telemetry.Absinthe, as: TelemetryAbsinthe

  test "calculate parent_path from path" do
    assert TelemetryAbsinthe.parent_path(["users", 5, "email"]) == ["users"]

    assert TelemetryAbsinthe.parent_path(["users", 5, "profile", "info"]) == [
             "users",
             5,
             "profile"
           ]

    assert TelemetryAbsinthe.parent_path(["users"]) == []
  end
end
