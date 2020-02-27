defmodule IntegrationTest do
  use ExUnit.Case
  alias NewRelic.Harvest.Collector

  @moduletag skip: "Tests requests to the Collector which require a license key"

  # env NR_INT_TEST=true mix test test/integration --include skip

  setup do
    System.put_env("NEW_RELIC_HARVEST_ENABLED", "true")
    Collector.AgentRun.reconnect()
    ensure_connect_cycle_complete()

    on_exit(fn ->
      System.delete_env("NEW_RELIC_HARVEST_ENABLED")
    end)

    :ok
  end

  test "Stores needed connect data" do
    assert Collector.AgentRun.account_id()
    assert Collector.AgentRun.primary_application_id()

    assert is_integer(Collector.AgentRun.lookup(:sampling_target))
    assert is_integer(Collector.AgentRun.lookup(:sampling_target_period))

    assert is_integer(Collector.AgentRun.lookup(:data_report_period))
    assert is_integer(Collector.AgentRun.lookup(:span_event_harvest_cycle))
  end

  test "connects to proper collector host" do
    {:ok, %{"redirect_host" => redirect_host}} = Collector.Protocol.preconnect()

    assert redirect_host =~ "collector-"
  end

  test "Agent re-connect ability" do
    previous_logger = GenServer.call(NewRelic.Logger, {:logger, :memory})
    original_agent_run_id = Collector.AgentRun.agent_run_id()

    Collector.AgentRun.reconnect()
    ensure_connect_cycle_complete()

    new_agent_run_id = Collector.AgentRun.agent_run_id()

    assert original_agent_run_id != new_agent_run_id

    log = GenServer.call(NewRelic.Logger, :flush)
    assert log =~ "Reporting to: https://"

    GenServer.call(NewRelic.Logger, {:replace, previous_logger})
  end

  test "Can post a metric" do
    ts_end = System.system_time(:second)
    ts_start = ts_end - 60
    agent_run_id = Collector.AgentRun.agent_run_id()

    data_array = [
      [
        %{name: "HttpDispatcher", scope: ""},
        [42, 0, 0, 0, 0, 0]
      ]
      # Other metrics
    ]

    {:ok, :accepted} =
      Collector.Protocol.metric_data([agent_run_id, ts_start, ts_end, data_array])
  end

  def ensure_connect_cycle_complete() do
    GenServer.cast(Collector.AgentRun, {:connect_cycle_complete?, self()})

    receive do
      :connect_cycle_complete -> :continue
    end
  end
end
