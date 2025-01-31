defmodule TelemetrySdk.DimensionalMetricsHarvesterTest do
  use ExUnit.Case

  alias NewRelic.Harvest
  alias NewRelic.Harvest.TelemetrySdk

  test "Harvester collects dimensional metrics" do
    {:ok, harvester} =
      DynamicSupervisor.start_child(
        TelemetrySdk.DimensionalMetrics.HarvesterSupervisor,
        TelemetrySdk.DimensionalMetrics.Harvester
      )

    metric1 = %{type: :gauge, name: "cpu", value: 10, attributes: %{k8: true, id: 123}}
    GenServer.cast(harvester, {:report, metric1})

    metrics = GenServer.call(harvester, :gather_harvest)
    assert length(metrics) > 0
  end

  test "harvest cycle" do
    original_env = Application.get_env(:new_relic_agent, :dimensional_metrics_harvest_cycle)

    Application.put_env(:new_relic_agent, :dimensional_metrics_harvest_cycle, 300)
    TestHelper.restart_harvest_cycle(TelemetrySdk.DimensionalMetrics.HarvestCycle)

    on_exit(fn ->
      TestHelper.reset_env(:dimensional_metrics_harvest_cycle, original_env)
    end)

    first = Harvest.HarvestCycle.current_harvester(TelemetrySdk.DimensionalMetrics.HarvestCycle)
    Process.monitor(first)

    # Wait until harvest swap
    assert_receive {:DOWN, _ref, _, ^first, :shutdown}, 1000

    second = Harvest.HarvestCycle.current_harvester(TelemetrySdk.DimensionalMetrics.HarvestCycle)
    Process.monitor(second)

    refute first == second
    assert Process.alive?(second)

    TestHelper.pause_harvest_cycle(TelemetrySdk.DimensionalMetrics.HarvestCycle)

    # Ensure the last harvester has shut down
    assert_receive {:DOWN, _ref, _, ^second, :shutdown}, 1000
  end

  test "Ignore late reports" do
    TestHelper.restart_harvest_cycle(TelemetrySdk.DimensionalMetrics.HarvestCycle)

    harvester =
      TelemetrySdk.DimensionalMetrics.HarvestCycle
      |> Harvest.HarvestCycle.current_harvester()

    assert :ok == GenServer.call(harvester, :send_harvest)

    GenServer.cast(harvester, {:report, :late_msg})

    assert :completed == GenServer.call(harvester, :send_harvest)

    TestHelper.pause_harvest_cycle(TelemetrySdk.DimensionalMetrics.HarvestCycle)
  end
end
