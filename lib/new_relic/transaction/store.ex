# NAME: Transaction.Sidecar?
defmodule NewRelic.Transaction.Store do
  @moduledoc false
  use GenServer, restart: :temporary

  @supervisor NewRelic.Transaction.StoreSupervisor
  @registry NewRelic.Transaction.Registry

  def track() do
    DynamicSupervisor.start_child(@supervisor, {__MODULE__, pid: self()})
  end

  def link(parent, child) do
    [{parent_store, _}] = Registry.lookup(@registry, parent)
    GenServer.cast(parent_store, {:link, child})
  end

  def add(attrs) do
    GenServer.cast(via(self()), {:add_attributes, attrs})
  end

  def add(pid, attrs) do
    GenServer.cast(via(pid), {:add_attributes, attrs})
  end

  def incr(attrs) do
    attrs
    |> Enum.map(fn {key, value} -> {key, {:counter, value}} end)
    |> add
  end

  def append(attrs) do
    attrs
    |> Enum.map(fn {key, value} -> {key, {:list, value}} end)
    |> add
  end

  def ignore() do
    GenServer.cast(via(self()), :ignore)
  end

  def complete() do
    GenServer.call(via(self()), :complete)
  end

  def dump() do
    GenServer.call(via(self()), :dump)
  end

  def start_link(pid: pid) do
    GenServer.start_link(__MODULE__, pid, name: via(pid))
  end

  def init(parent) do
    Process.monitor(parent)

    {:ok, %{parent: parent, offspring: MapSet.new(), attributes: []}}
  end

  def handle_cast({:add_attributes, attrs}, state) do
    {:noreply, %{state | attributes: attrs ++ state.attributes}}
  end

  def handle_cast(:ignore, _state) do
    {:stop, :normal, :ignored}
  end

  def handle_cast({:link, child}, state) do
    Process.monitor(child)
    Registry.register(@registry, child, nil)
    state = %{state | offspring: MapSet.put(state.offspring, child)}

    {:noreply, state}
  end

  def handle_call(:dump, _from, state) do
    {:reply, state, state}
  end

  def handle_call(:complete, _from, state) do
    run_complete(state)

    {:stop, :normal, :ok, :completed}
  end

  def handle_info({:DOWN, _, _, parent, _}, %{parent: parent} = state) do
    Registry.unregister(@registry, parent)
    Enum.each(state.offspring, &Registry.unregister(@registry, &1))

    {:noreply, state, {:continue, :complete}}
  end

  def handle_info({:DOWN, _, _, child, _}, state) do
    Registry.unregister(@registry, child)
    state = %{state | offspring: MapSet.put(state.offspring, child)}

    {:noreply, state}
  end

  def handle_continue(:complete, state) do
    run_complete(state)

    {:stop, :normal, :completed}
  end

  def via(pid) do
    {:via, Registry, {@registry, pid}}
  end

  def run_complete(%{parent: parent, attributes: attributes}) do
    attributes
    |> Enum.reduce(%{}, &collect_attr/2)
    # could do deep flatten, etc here
    # could save attrs in a map inline instead of list
    |> NewRelic.Transaction.Complete.run(parent)
  end

  def collect_attr({k, {:list, item}}, acc), do: Map.update(acc, k, [item], &[item | &1])
  def collect_attr({k, {:counter, n}}, acc), do: Map.update(acc, k, n, &(&1 + n))
  def collect_attr({k, v}, acc), do: Map.put(acc, k, v)
end
