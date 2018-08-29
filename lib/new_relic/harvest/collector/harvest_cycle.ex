defmodule NewRelic.Harvest.Collector.HarvestCycle do
  use GenServer

  # Manages the harvest cycle for a given harvester.

  @moduledoc false

  alias NewRelic.Harvest.Collector

  def start_link(config) do
    GenServer.start_link(__MODULE__, config, name: config[:name])
  end

  def init(
        name: name,
        harvest_cycle_key: harvest_cycle_key,
        module: module,
        supervisor: supervisor
      ) do
    if NewRelic.Config.enabled?(), do: send(self(), :harvest_cycle)

    {:ok,
     %{
       name: name,
       harvest_cycle_key: harvest_cycle_key,
       module: module,
       supervisor: supervisor,
       harvester: nil,
       timer: nil
     }}
  end

  # API

  def current_harvester(name), do: Collector.HarvesterStore.current(name)

  def manual_shutdown(name) do
    harvester = current_harvester(name)
    Process.monitor(harvester)
    GenServer.call(name, :pause)

    receive do
      {:DOWN, _ref, _, ^harvester, _reason} -> :ok
    after
      1000 -> NewRelic.log(:error, "Failed to shut down #{name}")
    end
  end

  # Server

  def handle_call(:restart, _from, %{timer: timer} = state) do
    stop_harvest_cycle(timer)
    harvester = swap_harvester(state)
    timer = trigger_harvest_cycle(state)
    {:reply, :ok, %{state | harvester: harvester, timer: timer}}
  end

  def handle_call(:pause, _from, %{harvester: harvester, timer: old_timer} = state) do
    stop_harvester(state, harvester)
    stop_harvest_cycle(old_timer)
    {:reply, :ok, %{state | harvester: nil, timer: nil}}
  end

  def handle_info(:harvest_cycle, state) do
    harvester = swap_harvester(state)
    timer = trigger_harvest_cycle(state)
    {:noreply, %{state | harvester: harvester, timer: timer}}
  end

  def handle_info(
        {:DOWN, _ref, _, pid, _reason},
        %{harvester: crashed_harvester, timer: old_timer} = state
      )
      when pid == crashed_harvester do
    stop_harvest_cycle(old_timer)
    harvester = swap_harvester(state)
    timer = trigger_harvest_cycle(state)
    {:noreply, %{state | harvester: harvester, timer: timer}}
  end

  def handle_info({:DOWN, _ref, _, _pid, _reason}, state) do
    {:noreply, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # Helpers

  defp swap_harvester(%{supervisor: supervisor, name: name, module: harvester_module}) do
    {:ok, next} = Supervisor.start_child(supervisor, [])
    Process.monitor(next)
    prev = Collector.HarvesterStore.current(name)
    Collector.HarvesterStore.update(name, next)
    harvester_module.complete(prev)
    next
  end

  defp stop_harvester(%{name: name, module: harvester_module}, harvester) do
    Collector.HarvesterStore.update(name, nil)
    harvester_module.complete(harvester)
  end

  defp stop_harvest_cycle(timer), do: timer && Process.cancel_timer(timer)

  defp trigger_harvest_cycle(%{harvest_cycle_key: harvest_cycle_key}) do
    harvest_cycle = Collector.AgentRun.lookup(harvest_cycle_key) || 60_000
    Process.send_after(self(), :harvest_cycle, harvest_cycle)
  end
end
