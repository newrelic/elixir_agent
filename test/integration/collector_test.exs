defmodule CollectorIntegrationTest do
  use ExUnit.Case
  alias NewRelic.Harvest.Collector

  @moduletag skip: "Tests requests to the Collector which require a license key"

  # mix test test/integration --include skip

  defmodule EvilCollectorPlug do
    import Plug.Conn

    def init(options), do: options

    def call(conn, test_pid: test_pid) do
      send(test_pid, :attempt)
      send_resp(conn, 503, ':(')
    end
  end

  setup do
    GenServer.call(Collector.AgentRun, :connected)
    System.put_env("NEW_RELIC_HARVEST_ENABLED", "true")

    on_exit(fn ->
      System.delete_env("NEW_RELIC_HARVEST_ENABLED")
    end)

    :ok
  end

  test "connects to proper collector host" do
    %{"redirect_host" => redirect_host} = Collector.Protocol.preconnect()
    assert redirect_host =~ "collector-"
  end

  test "handles invalid license key" do
    prev = Application.get_env(:new_relic, :harvest_enabled)
    System.put_env("NEW_RELIC_LICENSE_KEY", "invalid_key")

    assert {:error, :license_exception} = Collector.Protocol.preconnect()

    System.delete_env("NEW_RELIC_LICENSE_KEY")
    Application.put_env(:new_relic, :harvest_enabled, prev)
  end

  test "Can post a metric" do
    ts_end = System.system_time(:seconds)
    ts_start = ts_end - 60
    agent_run_id = Collector.AgentRun.agent_run_id()

    data_array = [
      [
        %{name: "HttpDispatcher", scope: ""},
        [42, 0, 0, 0, 0, 0]
      ]
      # Other metrics
    ]

    return_value = Collector.Protocol.metric_data([agent_run_id, ts_start, ts_end, data_array])
    assert return_value == []
  end
end
