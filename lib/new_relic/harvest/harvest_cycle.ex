defmodule NewRelic.Harvest.HarvestCycle do
  use GenServer

  # Manages the harvest cycle for a given harvester.

  @moduledoc false

  alias NewRelic.Harvest
  alias NewRelic.Harvest.HarvesterStore

  def start_link(config) do
    GenServer.start_link(__MODULE__, config, name: config[:name])
  end

  def init(
        name: name,
        child_spec: child_spec,
        harvest_cycle_key: harvest_cycle_key,
        supervisor: supervisor,
        lookup_module: lookup_module
      ) do
    if NewRelic.Config.enabled?(), do: send(self(), :harvest_cycle)

    {:ok,
     %{
       name: name,
       child_spec: child_spec,
       harvest_cycle_key: harvest_cycle_key,
       supervisor: supervisor,
       lookup_module: lookup_module,
       harvester: nil,
       timer: nil
     }}
  end

  # API

  def current_harvester(harvest_cycle), do: HarvesterStore.current(harvest_cycle)

  def cycle(harvest_cycle) do
    send(harvest_cycle, :harvest_cycle)
  end

  def manual_shutdown(harvest_cycle) do
    case current_harvester(harvest_cycle) do
      nil ->
        :ignore

      harvester ->
        Process.monitor(harvester)
        GenServer.call(harvest_cycle, :pause)

        receive do
          {:DOWN, _ref, _, ^harvester, _reason} ->
            NewRelic.log(:debug, "Completed shutdown #{inspect(harvest_cycle)}")
        end
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
    stop_harvest_cycle(state.timer)
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

  defp swap_harvester(%{
         supervisor: supervisor,
         name: name,
         harvester: harvester,
         child_spec: child_spec
       }) do
    {:ok, next} = Harvest.HarvesterSupervisor.start_child(supervisor, child_spec)
    Process.monitor(next)
    HarvesterStore.update(name, next)
    send_harvest(supervisor, harvester)
    next
  end

  defp stop_harvester(%{supervisor: supervisor, name: name, harvester: harvester}) do
    HarvesterStore.update(name, nil)
    send_harvest(supervisor, harvester)
  end

  def send_harvest(_supervisor, nil), do: :no_harvester

  @harvest_timeout 15_000
  def send_harvest(supervisor, harvester) do
    Task.Supervisor.start_child(
      Harvest.TaskSupervisor,
      fn ->
        try do
          GenServer.call(harvester, :send_harvest, @harvest_timeout)
        catch
          :exit, _exit ->
            NewRelic.log(:error, "Failed to send harvest from #{inspect(supervisor)}")
        end

        try do
          DynamicSupervisor.terminate_child(supervisor, harvester)
        catch
          :exit, _exit -> :ok
        end
      end,
      shutdown: @harvest_timeout
    )
  end

  defp stop_harvest_cycle(timer), do: timer && Process.cancel_timer(timer)

  defp trigger_harvest_cycle(%{
         lookup_module: lookup_module,
         harvest_cycle_key: harvest_cycle_key
       }) do
    harvest_cycle = lookup_module.lookup(harvest_cycle_key) || 60_000
    Process.send_after(self(), :harvest_cycle, harvest_cycle)
  end
end
