defmodule NewRelic.Transaction.StoreSupervisor do
  use DynamicSupervisor

  @moduledoc false

  def start_link() do
    DynamicSupervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  # max_children??
  def init(:ok) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
