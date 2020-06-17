defmodule TestHelper do
  def request(module, conn) do
    Plug.Cowboy.http(module, [],
      port: 8000,
      stream_handlers: [:cowboy_telemetry_h, :cowboy_stream_h]
    )

    {:ok, response} =
      NewRelic.Util.HTTP.get(
        "http://localhost:8000#{conn.request_path}",
        conn.req_headers
      )

    Plug.Cowboy.shutdown(Module.concat(module, HTTP))
    response
  end

  def trigger_report(module) do
    Process.sleep(300)
    GenServer.call(module, :report)
  end

  def gather_harvest(harvester) do
    Process.sleep(300)
    harvester.gather_harvest
  end

  def restart_harvest_cycle(harvest_cycle) do
    Process.sleep(300)
    GenServer.call(harvest_cycle, :restart)
  end

  def pause_harvest_cycle(harvest_cycle) do
    GenServer.call(harvest_cycle, :pause)
  end

  def find_metric(metrics, name, call_count \\ 1)

  def find_metric(metrics, {name, scope}, call_count) do
    Enum.find(metrics, fn
      [%{name: ^name, scope: ^scope}, [^call_count, _, _, _, _, _]] -> true
      _ -> false
    end)
  end

  def find_metric(metrics, name, call_count) do
    Enum.find(metrics, fn
      [%{name: ^name, scope: ""}, [^call_count, _, _, _, _, _]] -> true
      _ -> false
    end)
  end

  def http_request(path, port) do
    {:ok, {{_, _status_code, _}, _headers, body}} =
      :httpc.request('http://localhost:#{port}/#{path}')

    {:ok, %{body: to_string(body)}}
  end

  alias NewRelic.Harvest.Collector

  def simulate_agent_enabled(_context) do
    Process.whereis(Collector.TaskSupervisor) ||
      NewRelic.EnabledSupervisor.start_link(:ok)

    :ok
  end

  def simulate_agent_run(_context) do
    prev_key = Collector.AgentRun.trusted_account_key()
    Collector.AgentRun.store(:trusted_account_key, "190")
    System.put_env("NEW_RELIC_HARVEST_ENABLED", "true")
    System.put_env("NEW_RELIC_LICENSE_KEY", "foo")
    send(NewRelic.DistributedTrace.BackoffSampler, :reset)

    ExUnit.Callbacks.on_exit(fn ->
      Collector.AgentRun.store(:trusted_account_key, prev_key)
      System.delete_env("NEW_RELIC_HARVEST_ENABLED")
      System.delete_env("NEW_RELIC_LICENSE_KEY")
    end)

    :ok
  end
end
