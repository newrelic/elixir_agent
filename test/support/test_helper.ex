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
    GenServer.call(harvest_cycle, :restart)
  end

  def pause_harvest_cycle(harvest_cycle) do
    GenServer.call(harvest_cycle, :pause)
  end

  def find_metric(metrics, name, call_count \\ 1) do
    Enum.find(metrics, fn
      [%{name: ^name}, [^call_count, _, _, _, _, _]] -> true
      _ -> false
    end)
  end
end
