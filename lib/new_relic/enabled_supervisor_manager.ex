defmodule NewRelic.EnabledSupervisorManager do
  use GenServer

  # This "Manager" makes sure that we start the EnabledSupervisor
  # only after we have confirmed that we are connected

  @moduledoc false

  alias NewRelic.Harvest.Collector.AgentRun

  def start_link(name \\ __MODULE__) do
    GenServer.start_link(__MODULE__, :ok, name: name)
  end

  def init(:ok) do
    GenServer.cast(AgentRun, {:connect_cycle_complete?, self()})
    {:ok, %{}}
  end

  def handle_info(:connect_cycle_complete, state) do
    NewRelic.EnabledSupervisor.start_link()
    {:noreply, state}
  end
end
