# NAME: Transaction.Sidecar?
defmodule NewRelic.Transaction.Sidecar do
  @moduledoc false
  use GenServer, restart: :temporary

  @supervisor NewRelic.Transaction.SidecarSupervisor
  # @registry NewRelic.Transaction.Registry

  def start_link(pid: pid) do
    # GenServer.start_link(__MODULE__, pid, name: via(pid))
    GenServer.start_link(__MODULE__, pid)
  end

  def init(parent) do
    Process.monitor(parent)
    # IO.inspect({:SIDECAR, self()})
    # IO.inspect({:parent, parent})
    # Registry.register(@registry, parent, nil)
    send(parent, :ready!)

    {:ok, %{parent: parent, offspring: MapSet.new(), attributes: [], store: %{}}}
  end

  def track() do
    {:ok, sidecar} = DynamicSupervisor.start_child(@supervisor, {__MODULE__, pid: self()})
    Process.put(:nr_tx_sidecar, sidecar)

    receive do
      :ready! -> :ready!
    end
  end

  def spawn(parent, child, timestamp) do
    find_tx_sidecar(parent)
    |> GenServer.cast({:spawn, parent, child, timestamp})
  end

  def tracking?() do
    # Registry.lookup(@registry, self()) != []
    find_tx_sidecar() != nil
  end

  def add(attrs) do
    find_tx_sidecar()
    |> IO.inspect(label: "add #{inspect(attrs)}")
    |> GenServer.cast({:add_attributes, attrs})
  end

  def add(pid, attrs) do
    find_tx_sidecar(pid)
    |> IO.inspect(label: "add #{inspect(attrs)}")
    |> GenServer.cast({:add_attributes, attrs})
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

  def set(key, value) do
    with sidecar when is_pid(sidecar) <- find_tx_sidecar() do
      GenServer.call(sidecar, {:set, key, value})
    end
  end

  def get(key) do
    with sidecar when is_pid(sidecar) <- find_tx_sidecar() do
      GenServer.call(sidecar, {:get, key})
    end
  end

  def ignore() do
    with sidecar when is_pid(sidecar) <- find_tx_sidecar() do
      GenServer.call(sidecar, :ignore)
    end
  end

  def complete() do
    with sidecar when is_pid(sidecar) <- find_tx_sidecar() do
      GenServer.call(sidecar, :complete)
    end
  end

  def dump() do
    with sidecar when is_pid(sidecar) <- find_tx_sidecar() do
      GenServer.call(sidecar, :dump)
    end
  end

  def handle_cast({:add_attributes, attrs}, state) do
    {:noreply, %{state | attributes: attrs ++ state.attributes}}
  end

  def handle_cast({:spawn, parent, child, timestamp}, state) do
    Process.monitor(child)

    spawn_attrs = [
      trace_process_spawns: {:list, {child, timestamp, parent}},
      trace_process_names: {:list, {child, NewRelic.Util.process_name(child)}}
    ]

    {:noreply,
     %{
       state
       | attributes: spawn_attrs ++ state.attributes,
         offspring: MapSet.put(state.offspring, child)
     }}
  end

  def handle_call({:set, key, value}, _from, state) do
    {:reply, :ok, put_in(state, [:store, key], value)}
  end

  def handle_call({:get, key}, _from, state) do
    {:reply, Map.get(state.store, key), state}
  end

  def handle_call(:dump, _from, state) do
    {:reply, state, state}
  end

  def handle_call(:ignore, _from, _state) do
    {:stop, :normal, :ok, :ignored}
  end

  def handle_call(:complete, _from, state) do
    run_complete(state)

    {:stop, :normal, :ok, :completed}
  end

  def handle_info({:DOWN, _, _, parent, _}, %{parent: parent} = state) do
    {:noreply, state, {:continue, :complete}}
  end

  def handle_info({:DOWN, _, _, child, _}, state) do
    exit_attrs = [trace_process_exits: {:list, {child, System.system_time(:millisecond)}}]

    {:noreply, %{state | attributes: exit_attrs ++ state.attributes}}
  end

  def handle_continue(:complete, state) do
    run_complete(state)

    {:stop, :normal, :completed}
  end

  def find_tx_sidecar(pid) do
    # IO.inspect({:find_tx_sidecar, pid})

    with {:dictionary, dictionary} <- Process.info(pid, :dictionary) do
      # IO.inspect({:find_tx_sidecar, pid, dictionary})

      Keyword.get(dictionary, :nr_tx_sidecar, nil) ||
        Enum.find_value(Keyword.get(dictionary, :"$callers", []), &look_for_sidecar/1) ||
        Enum.find_value(Keyword.get(dictionary, :"$ancestors", []), &look_for_sidecar/1)
    end
  end

  def find_tx_sidecar() do
    # IO.inspect :find_tx_sidecar
    case Process.get(:nr_tx_sidecar) do
      nil -> determine_tx_sidecar()
      :no_track -> nil
      pid -> pid
    end
  end

  def determine_tx_sidecar() do
    # IO.inspect {:determine_tx_sidecar, self()}
    res =
      Enum.find_value(Process.get(:"$callers") || [], &look_for_sidecar_and_save/1) ||
        Enum.find_value(Process.get(:"$ancestors") || [], &look_for_sidecar_and_save/1) ||
        no_tx_sidecar_found()

    # IO.inspect(res, label: "determine_tx_sidecar #{inspect self()}")
    res
  end

  def no_tx_sidecar_found() do
    # Process.put(:nr_tx_sidecar, :no_track)
    nil
  end

  def look_for_sidecar_and_save(pid) do
    # IO.inspect {:look_for_sidecar_and_save, pid}
    with sidecar when is_pid(sidecar) <- look_for_sidecar(pid) do
      # IO.inspect {:FOUND, :in, self(), :sidecar, sidecar}
      Process.put(:nr_tx_sidecar, sidecar)
      sidecar
    end
  end

  def look_for_sidecar(pid) when is_pid(pid) do
    # IO.inspect({:look_for_sidecar, pid})
    # case Registry.lookup(@registry, pid) do
    #   [{sidecar, _}] -> sidecar
    #   [] -> nil
    # end
    with {:dictionary, dictionary} <- Process.info(pid, :dictionary) do
      # IO.inspect dictionary, label: inspect(pid)
      case Keyword.get(dictionary, :nr_tx_sidecar) do
        nil -> nil
        :no_track -> nil
        sidecar -> sidecar
      end
      # |> IO.inspect(label: "nr_tx_sidecar #{inspect(pid)}")
    end
  end

  def look_for_sidecar(_named_process), do: nil

  def run_complete(%{parent: parent, attributes: attributes}) do
    attributes
    |> Enum.reverse()
    |> Enum.reduce(%{}, &collect_attr/2)
    # tx that ends via DOWN doesn't get needed closing attributes, so:
    |> Map.put_new(:end_time_mono, System.monotonic_time())
    # could do deep flatten, etc here
    # could save attrs in a map inline instead of list
    |> NewRelic.Transaction.Complete.run(parent)
  end

  def collect_attr({k, {:list, item}}, acc), do: Map.update(acc, k, [item], &[item | &1])
  def collect_attr({k, {:counter, n}}, acc), do: Map.update(acc, k, n, &(&1 + n))
  def collect_attr({k, v}, acc), do: Map.put(acc, k, v)
end
