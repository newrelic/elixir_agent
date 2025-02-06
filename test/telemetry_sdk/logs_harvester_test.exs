defmodule TelemetrySdk.LogsHarvesterTest do
  use ExUnit.Case

  alias NewRelic.Harvest
  alias NewRelic.Harvest.TelemetrySdk

  test "Harvester collect logs" do
    {:ok, harvester} =
      DynamicSupervisor.start_child(
        TelemetrySdk.Logs.HarvesterSupervisor,
        TelemetrySdk.Logs.Harvester
      )

    log1 = %{}
    GenServer.cast(harvester, {:report, log1})

    logs = GenServer.call(harvester, :gather_harvest)
    assert length(logs) > 0
  end

  test "harvest cycle" do
    TestHelper.run_with(:application_config, logs_harvest_cycle: 300)
    TestHelper.restart_harvest_cycle(TelemetrySdk.Logs.HarvestCycle)

    first = Harvest.HarvestCycle.current_harvester(TelemetrySdk.Logs.HarvestCycle)
    Process.monitor(first)

    # Wait until harvest swap
    assert_receive {:DOWN, _ref, _, ^first, :shutdown}, 1000

    second = Harvest.HarvestCycle.current_harvester(TelemetrySdk.Logs.HarvestCycle)
    Process.monitor(second)

    refute first == second
    assert Process.alive?(second)

    TestHelper.pause_harvest_cycle(TelemetrySdk.Logs.HarvestCycle)

    # Ensure the last harvester has shut down
    assert_receive {:DOWN, _ref, _, ^second, :shutdown}, 1000
  end

  test "Ignore late reports" do
    TestHelper.restart_harvest_cycle(TelemetrySdk.Logs.HarvestCycle)

    harvester =
      TelemetrySdk.Logs.HarvestCycle
      |> Harvest.HarvestCycle.current_harvester()

    assert :ok == GenServer.call(harvester, :send_harvest)

    GenServer.cast(harvester, {:report, :late_msg})

    assert :completed == GenServer.call(harvester, :send_harvest)

    TestHelper.pause_harvest_cycle(TelemetrySdk.Logs.HarvestCycle)
  end
end
