defmodule IntegrationTest do
  use ExUnit.Case
  alias NewRelic.Harvest.Collector

  @moduletag skip: "Tests requests to the Collector which require a license key"

  # env NR_INT_TEST=true mix test test/integration --include skip

  setup do
    reset_config = TestHelper.update(:nr_config, harvest_enabled: true)
    Collector.AgentRun.reconnect()
    GenServer.call(Collector.AgentRun, :ping)

    on_exit(fn ->
      reset_config.()
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
    GenServer.call(Collector.AgentRun, :ping)

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

  test "Can post a Log" do
    {:ok, resp} =
      NewRelic.Harvest.TelemetrySdk.API.post(
        :log,
        [%{logs: [%{message: "TEST"}], common: %{}}]
      )

    assert resp.status_code == 202
  end

  test "EnabledSupervisor starts" do
    # make sure a process under EnabledSupervisor started
    assert Process.whereis(NewRelic.Sampler.Beam)
  end
end
