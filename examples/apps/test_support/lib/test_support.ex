defmodule TestSupport do
  def gather_harvest(harvester) do
    Process.sleep(300)
    harvester.gather_harvest
  end

  def restart_harvest_cycle(harvest_cycle) do
    Process.sleep(300)
    GenServer.call(harvest_cycle, :restart)
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

  def simulate_agent_enabled(_context) do
    Process.whereis(Harvest.TaskSupervisor) ||
      NewRelic.EnabledSupervisor.start_link(:ok)

    :ok
  end

  def simulate_agent_run(_context, extra_config) do
    reset_config =
      update(
        :nr_config,
        Keyword.merge([license_key: "dummy_key", harvest_enabled: true], extra_config)
      )

    reset_agent_run = update(:nr_agent_run, trusted_account_key: "190")
    send(NewRelic.DistributedTrace.BackoffSampler, :reset)

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
