defmodule NewRelic.DistributedTrace.Tracker do
  use GenServer

  @moduledoc false

  def start_link() do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def init(:ok) do
    :ets.new(__MODULE__, [:named_table, :public, :set])
    NewRelic.sample_process()
    {:ok, %{}}
  end

  def store(pid, context: context) do
    :ets.insert(__MODULE__, {pid, context})
  end

  def fetch(pid) do
    case :ets.lookup(__MODULE__, pid) do
      [{^pid, context}] -> context
      [] -> nil
    end
  end

  def cleanup(pid) do
    :ets.delete(__MODULE__, pid)
  end
end
