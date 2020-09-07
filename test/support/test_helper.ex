defmodule TestHelper do
  def request(module, conn) do
    Task.async(fn ->
      try do
        module.call(conn, [])
      rescue
        error -> error
      end
    end)
    |> Task.await()
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
    Process.whereis(Harvest.TaskSupervisor) ||
      NewRelic.EnabledSupervisor.start_link(:ok)

    :ok
  end

  def simulate_agent_run(_context) do
    prev_key = Collector.AgentRun.trusted_account_key()
    Collector.AgentRun.store(:trusted_account_key, "190")
    reset_config = TestHelper.update(:nr_config, license_key: "dummy_key", harvest_enabled: true)
    send(NewRelic.DistributedTrace.BackoffSampler, :reset)

    ExUnit.Callbacks.on_exit(fn ->
      Collector.AgentRun.store(:trusted_account_key, prev_key)
      reset_config.()
    end)

    :ok
  end

  def update(key, items) do
    original = :persistent_term.get(key)
    items = Map.new(items)

    :persistent_term.put(key, Map.merge(original, items))

    Map.take(original, Map.keys(items))

    fn ->
      :persistent_term.put(key, original)
    end
  end
end
