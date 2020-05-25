# NAME: Transaction.Sidecar?
defmodule NewRelic.Transaction.Store do
  @moduledoc false
  use GenServer

  @supervisor NewRelic.Transaction.StoreSupervisor
  @registry NewRelic.Transaction.Registry

  def track() do
    DynamicSupervisor.start_child(@supervisor, {__MODULE__, pid: self()})
  end

  def link(parent, child) do
    [{parent_store, _}] = Registry.lookup(@registry, parent)
    GenServer.call(parent_store, {:link, child})
  end

  def add(attrs) do
    GenServer.cast(via(self()), {:add_attributes, attrs})
  end

  def incr(attrs) do
    attrs
    |> Enum.map(fn {key, value} -> {key, {:counter, value}} end)
    |> add
  end

  def ignore() do
    # Shut down w/o sending data
  end

  def complete() do
    # Shut down & log data
    # :sync version - must await til finished
  end

  def dump() do
    GenServer.call(via(self()), :dump)
  end

  def start_link(pid: pid) do
    GenServer.start_link(__MODULE__, pid, name: via(pid))
  end

  def init(parent) do
    Process.monitor(parent)

    {:ok,
     %{
       parent: parent,
       offspring: MapSet.new(),
       attributes: []
     }}
  end

  def handle_cast({:add_attributes, attrs}, state) do
    {:noreply, %{state | attributes: attrs ++ state.attributes}}
  end

  def handle_call({:link, child}, _from, state) do
    Process.monitor(child)
    Registry.register(@registry, child, nil)
    state = %{state | offspring: MapSet.put(state.offspring, child)}

    {:reply, :ok, state}
  end

  def handle_call(:dump, _from, state) do
    {:reply, state, state}
  end

  # TODO: handle non-process Transaction complete

  def handle_info({:DOWN, _, _, parent, _}, %{parent: parent} = state) do
    Registry.unregister(@registry, parent)
    Enum.each(state.offspring, &Registry.unregister(@registry, &1))

    # Kick off the Transaction complete process
    #  :continue ?
    IO.inspect({:DOWN, :complete, parent, state})

    state.attributes
    |> Enum.reduce(%{}, &collect_attr/2)
    |> NewRelic.Transaction.Complete.run(parent)

    {:noreply, state}
  end

  def handle_info({:DOWN, _, _, child, _}, state) do
    Registry.unregister(@registry, child)
    state = %{state | offspring: MapSet.put(state.offspring, child)}

    {:noreply, state}
  end

  def via(pid) do
    {:via, Registry, {@registry, pid}}
  end

  def collect_attr({k, {:list, item}}, acc), do: Map.update(acc, k, [item], &[item | &1])
  def collect_attr({k, {:counter, n}}, acc), do: Map.update(acc, k, n, &(&1 + n))
  def collect_attr({k, v}, acc), do: Map.put(acc, k, v)
end
