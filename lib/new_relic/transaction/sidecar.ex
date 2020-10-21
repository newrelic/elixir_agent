defmodule NewRelic.Transaction.Sidecar do
  @moduledoc false
  use GenServer, restart: :temporary

  def setup_stores do
    :ets.new(__MODULE__.ContextStore, [:named_table, :set, :public, read_concurrency: true])
    :ets.new(__MODULE__.LookupStore, [:named_table, :set, :public, read_concurrency: true])
    :persistent_term.put({__MODULE__, :counter}, :counters.new(1, []))
  end

  def track(type) do
    {:ok, sidecar} = GenServer.start(__MODULE__, {self(), type})

    store_sidecar(self(), sidecar)
    set_sidecar(sidecar)

    receive do
      :sidecar_ready -> :ok
    end
  end

  def init({parent, type}) do
    Process.monitor(parent)
    send(parent, :sidecar_ready)
    counter(:add)

    {:ok,
     %{
       start_time: System.system_time(:millisecond),
       type: type,
       parent: parent,
       exclusions: [],
       offspring: MapSet.new(),
       attributes: []
     }}
  end

  def connect_parent() do
    store_sidecar(self(), get_sidecar())
    cast({:add_offspring, self()})
  end

  def tracking?() do
    is_pid(get_sidecar())
  end

  def track_spawn(parent, child, timestamp) do
    parent_sidecar = lookup_sidecar(parent)
    store_sidecar(child, parent_sidecar)
    cast(parent_sidecar, {:spawn, parent, child, timestamp})
  end

  def add(attrs) do
    cast({:add_attributes, attrs})
  end

  def incr(attrs) do
    attrs
    |> wrap(:counter)
    |> add()
  end

  def append(attrs) do
    attrs
    |> wrap(:list)
    |> add()
  end

  def trace_context(context) do
    :ets.insert(__MODULE__.ContextStore, {{:context, get_sidecar()}, context})
  end

  def trace_context() do
    case :ets.lookup(__MODULE__.ContextStore, {:context, get_sidecar()}) do
      [{_, value}] -> value
      [] -> nil
    end
  end

  def ignore() do
    cast(:ignore)
    set_sidecar(:no_track)
  end

  def exclude() do
    cast({:exclude, self()})
    set_sidecar(:no_track)
  end

  def complete() do
    with sidecar when is_pid(sidecar) <- get_sidecar() do
      cleanup(context: sidecar)
      cleanup(lookup: self())
      clear_sidecar()
      cast(sidecar, :complete)
    end
  end

  defp cast(message) do
    GenServer.cast(get_sidecar(), message)
  end

  defp cast(sidecar, message) do
    GenServer.cast(sidecar, message)
  end

  def handle_cast({:add_attributes, attrs}, state) do
    {:noreply, %{state | attributes: attrs ++ state.attributes}}
  end

  def handle_cast({:spawn, _parent, _child, timestamp}, %{start_time: start_time} = state)
      when timestamp < start_time do
    {:noreply, state}
  end

  def handle_cast({:spawn, parent, child, timestamp}, state) do
    Process.monitor(child)

    spawn_attrs = [
      process_spawns: {:list, {child, timestamp, parent, NewRelic.Util.process_name(child)}}
    ]

    {:noreply,
     %{
       state
       | attributes: spawn_attrs ++ state.attributes,
         offspring: MapSet.put(state.offspring, child)
     }}
  end

  def handle_cast({:exclude, pid}, state) do
    {:noreply, %{state | exclusions: [pid | state.exclusions]}}
  end

  def handle_cast({:add_offspring, pid}, state) do
    {:noreply, %{state | offspring: MapSet.put(state.offspring, pid)}}
  end

  def handle_cast(:ignore, state) do
    cleanup(context: self())
    cleanup(lookup: state.parent)
    {:stop, :normal, state}
  end

  def handle_cast(:complete, state) do
    {:noreply, state, {:continue, :complete}}
  end

  def handle_info(
        {:DOWN, _, _, parent, down_reason},
        %{type: :other, parent: parent} = state
      ) do
    attributes = state.attributes

    attributes =
      with {reason, stack} when reason != :shutdown <- down_reason do
        error_attrs = [
          error: true,
          error_kind: :exit,
          error_reason: inspect(reason),
          error_stack: inspect(stack)
        ]

        error_attrs ++ attributes
      else
        _ -> attributes
      end

    attributes = Keyword.put_new(attributes, :end_time_mono, System.monotonic_time())

    {:noreply, %{state | attributes: attributes}, {:continue, :complete}}
  end

  def handle_info({:DOWN, _, _, child, _}, state) do
    exit_attrs = [process_exits: {:list, {child, System.system_time(:millisecond)}}]

    {:noreply, %{state | attributes: exit_attrs ++ state.attributes}}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  def handle_continue(:complete, state) do
    cleanup(context: self())
    Enum.each(state.offspring, &cleanup(lookup: &1))
    run_complete(state)
    counter(:sub)
    {:stop, :normal, :completed}
  end

  defp clear_sidecar() do
    Process.delete(:nr_tx_sidecar)
  end

  defp set_sidecar(nil) do
    nil
  end

  defp set_sidecar(pid) do
    Process.put(:nr_tx_sidecar, pid)
    pid
  end

  defp get_sidecar() do
    case Process.get(:nr_tx_sidecar) do
      nil ->
        sidecar =
          lookup_sidecar_in(process_callers()) ||
            lookup_sidecar_in(process_ancestors())

        set_sidecar(sidecar)

      :no_track ->
        nil

      pid ->
        pid
    end
  end

  defp lookup_sidecar_in(processes) do
    Enum.find_value(processes, &lookup_sidecar/1)
  end

  defp store_sidecar(_, nil), do: :no_sidecar

  defp store_sidecar(pid, sidecar) do
    :ets.insert(__MODULE__.LookupStore, {pid, sidecar})
  end

  defp lookup_sidecar(pid) when is_pid(pid) do
    case :ets.lookup(__MODULE__.LookupStore, pid) do
      [{_, sidecar}] -> sidecar
      [] -> nil
    end
  end

  defp lookup_sidecar(_named_process), do: nil

  defp process_callers() do
    Process.get(:"$callers", []) |> Enum.reverse()
  end

  defp process_ancestors() do
    Process.get(:"$ancestors", [])
  end

  defp cleanup(context: sidecar) do
    :ets.delete(__MODULE__.ContextStore, {:context, sidecar})
  end

  defp cleanup(lookup: root) do
    :ets.delete(__MODULE__.LookupStore, root)
  end

  def counter() do
    :counters.get(:persistent_term.get({__MODULE__, :counter}), 1)
  end

  defp counter(:add) do
    :counters.add(:persistent_term.get({__MODULE__, :counter}), 1, 1)
  end

  defp counter(:sub) do
    :counters.sub(:persistent_term.get({__MODULE__, :counter}), 1, 1)
  end

  defp run_complete(%{attributes: attributes} = state) do
    attributes
    |> Enum.reverse()
    |> Enum.reject(&exclude_attrs(&1, state.exclusions))
    |> Enum.reduce(%{}, &collect_attr/2)
    |> NewRelic.Transaction.Complete.run(state.parent)
  end

  defp wrap(attrs, tag) do
    Enum.map(attrs, fn {key, value} -> {key, {tag, value}} end)
  end

  defp exclude_attrs({:process_spawns, {:list, {pid, _, _, _}}}, exclusions),
    do: pid in exclusions

  defp exclude_attrs(_, _), do: false

  defp collect_attr({k, {:list, item}}, acc), do: Map.update(acc, k, [item], &[item | &1])
  defp collect_attr({k, {:counter, n}}, acc), do: Map.update(acc, k, n, &(&1 + n))
  defp collect_attr({k, v}, acc), do: Map.put(acc, k, v)
end
