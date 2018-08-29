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
    Process.sleep(200)
    GenServer.call(module, :report)
  end

  def gather_harvest(harvester) do
    Process.sleep(200)
    harvester.gather_harvest
  end

  def restart_harvest_cycle(harvest_cycle) do
    GenServer.call(harvest_cycle, :restart)
  end

  def pause_harvest_cycle(harvest_cycle) do
    GenServer.call(harvest_cycle, :pause)
  end
end

ExUnit.start()

System.at_exit(fn _ ->
  IO.puts(GenServer.call(NewRelic.Logger, :flush))
end)
