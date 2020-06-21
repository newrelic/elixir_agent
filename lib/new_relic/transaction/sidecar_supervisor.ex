defmodule NewRelic.Transaction.SidecarSupervisor do
  use DynamicSupervisor

  @moduledoc false

  def start_link(_) do
    DynamicSupervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  # TODO: overload protection via max_children??
  def init(:ok) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
