defmodule TestSupport do
  # def trigger_report(module) do
  #   Process.sleep(300)
  #   GenServer.call(module, :report)
  # end

  def gather_harvest(harvester) do
    Process.sleep(300)
    harvester.gather_harvest()
  end

  def restart_harvest_cycle(harvest_cycle) do
    Process.sleep(300)
    GenServer.call(harvest_cycle, :restart)
  end

  # def pause_harvest_cycle(harvest_cycle) do
  #   GenServer.call(harvest_cycle, :pause)
  # end

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

  def find_span(spans, name) do
    Enum.find_value(spans, fn
      [%{name: ^name} = span, _, _] -> span
      _span -> false
    end)
  end

  def simulate_agent_enabled(_context) do
    Process.whereis(Harvest.TaskSupervisor) ||
      NewRelic.EnabledSupervisor.start_link(:ok)

    :ok
  end

  def simulate_agent_run(_context) do
    reset_config = update(:nr_config, license_key: "dummy_key", harvest_enabled: true)
    reset_agent_run = update(:nr_agent_run, trusted_account_key: "190")
    NewRelic.DistributedTrace.BackoffSampler.reset()

    ExUnit.Callbacks.on_exit(fn ->
      reset_config.()
      reset_agent_run.()
    end)

    :ok
  end

  defp update(key, updates) do
    original = :persistent_term.get(key, %{})
    updates = Map.new(updates)

    :persistent_term.put(key, Map.merge(original, updates))

    fn -> :persistent_term.put(key, original) end
  end
end
