defmodule NewRelic.EnabledSupervisorManager do
  use DynamicSupervisor

  @moduledoc false

  def start_link(_) do
    DynamicSupervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def init(:ok) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def start_child() do
    DynamicSupervisor.start_child(__MODULE__, NewRelic.EnabledSupervisor)
  end
end
