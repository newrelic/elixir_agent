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
        supervisor: supervisor
      ) do
    if NewRelic.Config.enabled?(), do: send(self(), :harvest_cycle)

    {:ok,
     %{
       name: name,
       harvest_cycle_key: harvest_cycle_key,
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
      {:DOWN, _ref, _, ^harvester, _reason} ->
        NewRelic.log(:warn, "Completed shutdown #{inspect(name)}")
    end
  end

  # Server

  def handle_call(:restart, _from, %{timer: timer} = state) do
    stop_harvest_cycle(timer)
    harvester = swap_harvester(state)
    timer = trigger_harvest_cycle(state)
    {:reply, :ok, %{state | harvester: harvester, timer: timer}}
  end

  def handle_call(:pause, _from, %{timer: old_timer} = state) do
    stop_harvester(state)
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

  defp swap_harvester(%{supervisor: supervisor, name: name, harvester: harvester}) do
    {:ok, next} = Supervisor.start_child(supervisor, [])
    Process.monitor(next)
    Collector.HarvesterStore.update(name, next)
    send_harvest(supervisor, harvester)
    next
  end

  defp stop_harvester(%{supervisor: supervisor, name: name, harvester: harvester}) do
    Collector.HarvesterStore.update(name, nil)
    send_harvest(supervisor, harvester)
  end

  def send_harvest(_supervisor, nil), do: :no_harvester

  @harvest_timeout 15_000
  def send_harvest(supervisor, harvester) do
    Task.Supervisor.start_child(
      Collector.TaskSupervisor,
      fn ->
        try do
          GenServer.call(harvester, :send_harvest, @harvest_timeout)
        catch
          :exit, _exit ->
            NewRelic.log(:error, "Failed to send harvest from #{inspect(supervisor)}")
        after
          Supervisor.terminate_child(supervisor, harvester)
        end
      end,
      shutdown: @harvest_timeout
    )
  end

  defp stop_harvest_cycle(timer), do: timer && Process.cancel_timer(timer)

  defp trigger_harvest_cycle(%{harvest_cycle_key: harvest_cycle_key}) do
    harvest_cycle = Collector.AgentRun.lookup(harvest_cycle_key) || 60_000
    Process.send_after(self(), :harvest_cycle, harvest_cycle)
  end
end
