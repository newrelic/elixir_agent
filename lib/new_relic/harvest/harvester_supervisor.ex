defmodule NewRelic.Harvest.HarvesterSupervisor do
  use DynamicSupervisor

  @moduledoc false

  def start_link(harvester: harvester, name: name) do
    DynamicSupervisor.start_link(__MODULE__, harvester, name: name)
  end

  def start_child(supervisor, harvester) do
    DynamicSupervisor.start_child(supervisor, harvester)
  end

  def init(_harvester) do
    DynamicSupervisor.init(strategy: :one_for_one, max_restarts: 10)
  end
end
