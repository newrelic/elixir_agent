defmodule AgentRunIntegrationTest do
  use ExUnit.Case
  alias NewRelic.Harvest.Collector

  @moduletag skip: "Tests requests to the Collector which require a license key"

  # mix test test/integration --include skip

  setup do
    Collector.AgentRun.reconnect()
    GenServer.call(Collector.AgentRun, :connected)
    System.put_env("NEW_RELIC_HARVEST_ENABLED", "true")

    on_exit(fn ->
      System.delete_env("NEW_RELIC_HARVEST_ENABLED")
    end)

    :ok
  end

  test "has util data in connect payload" do
    payload = Collector.Connect.payload()
    ram = get_in(payload, [Access.at(0), :utilization, :total_ram_mib])
    assert is_integer(ram)
  end

  test "Stores needed connect data" do
    assert Collector.AgentRun.account_id()
    assert Collector.AgentRun.primary_application_id()

    assert is_integer(NewRelic.Harvest.Collector.AgentRun.lookup(:sampling_target))
    assert is_integer(NewRelic.Harvest.Collector.AgentRun.lookup(:sampling_target_period))

    assert is_integer(NewRelic.Harvest.Collector.AgentRun.lookup(:data_report_period))
    assert is_integer(NewRelic.Harvest.Collector.AgentRun.lookup(:span_event_harvest_cycle))
  end

  test "Agent re-connect ability" do
    original_agent_run_id = Collector.AgentRun.agent_run_id()

    Collector.AgentRun.reconnect()
    GenServer.call(Collector.AgentRun, :connected)

    new_agent_run_id = Collector.AgentRun.agent_run_id()

    assert original_agent_run_id != new_agent_run_id
  end
end
