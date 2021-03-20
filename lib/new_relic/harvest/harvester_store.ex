defmodule NewRelic.Harvest.HarvesterStore do
  use GenServer

  # Wrapper around an ETS table that tracks the current harvesters

  @moduledoc false

  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def init(:ok) do
    NewRelic.sample_process()
    :ets.new(__MODULE__, [:named_table, :set, :public, read_concurrency: true])
    {:ok, %{}}
  end

  def current(harvester) do
    case :ets.lookup(__MODULE__, harvester) do
      [{^harvester, pid}] -> pid
      _ -> nil
    end
  rescue
    _ -> nil
  end

  def update(harvester, pid) do
    :ets.insert(__MODULE__, {harvester, pid})
  end
end
