defmodule TelemetrySdk.SpanHarvesterTest do
  use ExUnit.Case

  alias NewRelic.Harvest
  alias NewRelic.Harvest.TelemetrySdk

  test "Harvester collect spans" do
    {:ok, harvester} =
      DynamicSupervisor.start_child(
        TelemetrySdk.Spans.HarvesterSupervisor,
        TelemetrySdk.Spans.Harvester
      )

    span1 = %{}
    GenServer.cast(harvester, {:report, span1})

    spans = GenServer.call(harvester, :gather_harvest)
    assert length(spans) > 0
  end

  test "harvest cycle" do
    original_env = Application.get_env(:new_relic_agent, :spans_harvest_cycle)
    on_exit(fn -> TestHelper.reset_env(:spans_harvest_cycle, original_env) end)

    Application.put_env(:new_relic_agent, :spans_harvest_cycle, 300)

    TestHelper.restart_harvest_cycle(TelemetrySdk.Spans.HarvestCycle)

    first = Harvest.HarvestCycle.current_harvester(TelemetrySdk.Spans.HarvestCycle)
    Process.monitor(first)

    # Wait until harvest swap
    assert_receive {:DOWN, _ref, _, ^first, :shutdown}, 1000

    second = Harvest.HarvestCycle.current_harvester(TelemetrySdk.Spans.HarvestCycle)
    Process.monitor(second)

    refute first == second
    assert Process.alive?(second)

    TestHelper.pause_harvest_cycle(TelemetrySdk.Spans.HarvestCycle)

    # Ensure the last harvester has shut down
    assert_receive {:DOWN, _ref, _, ^second, :shutdown}, 1000
  end

  test "Ignore late reports" do
    TestHelper.restart_harvest_cycle(TelemetrySdk.Spans.HarvestCycle)

    harvester =
      TelemetrySdk.Spans.HarvestCycle
      |> Harvest.HarvestCycle.current_harvester()

    assert :ok == GenServer.call(harvester, :send_harvest)

    GenServer.cast(harvester, {:report, :late_msg})

    assert :completed == GenServer.call(harvester, :send_harvest)

    TestHelper.pause_harvest_cycle(TelemetrySdk.Spans.HarvestCycle)
  end
end
