defmodule NewRelic.Transaction.Sidecar do
  use GenServer, restart: :temporary

  @moduledoc false

  alias NewRelic.Transaction.ErlangTrace

  def setup_stores do
    :ets.new(__MODULE__.ContextStore, [:named_table, :set, :public, read_concurrency: true])
    :ets.new(__MODULE__.LookupStore, [:named_table, :set, :public, read_concurrency: true])
    :persistent_term.put({__MODULE__, :counter}, :counters.new(1, []))
  end

  def track(type) do
    # We use `GenServer.start` to avoid a bi-directional link
    # and guarantee that we never crash the Transaction process
    # even in the case of an unexpected bug. Additionally, this
    # blocks the Transaction process the smallest amount possible
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
       attributes: %{}
     }}
  end

  def connect(%{sidecar: nil}), do: :ignore

  def connect(%{sidecar: sidecar, parent: parent}) do
    with nil <- get_sidecar() do
      cast(sidecar, {:spawn, parent, self(), System.system_time(:millisecond)})
      store_sidecar(self(), sidecar)
      set_sidecar(sidecar)
      ErlangTrace.trace()
    end
  end

  def disconnect() do
    set_sidecar(:no_track)
    cleanup(lookup: self())
  end

  def tracking?() do
    is_pid(get_sidecar())
  end

  def track_spawn(parent, child, timestamp) do
    with parent_sidecar when is_pid(parent_sidecar) <- lookup_sidecar(parent) do
      store_sidecar(child, parent_sidecar)
      cast(parent_sidecar, {:spawn, parent, child, timestamp})
      parent_sidecar
    end
  end

  def add(attrs) do
    cast({:add_attributes, attrs})
  end

  def incr(attrs) do
    cast({:incr_attributes, attrs})
  end

  def append(attrs) do
    cast({:append_attributes, attrs})
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
    attributes = Map.merge(state.attributes, Map.new(attrs))
    {:noreply, %{state | attributes: attributes}}
  end

  def handle_cast({:incr_attributes, attrs}, state) do
    attributes =
      Enum.reduce(attrs, state.attributes, fn {key, val}, acc ->
        Map.update(acc, key, val, &(&1 + val))
      end)

    {:noreply, %{state | attributes: attributes}}
  end

  def handle_cast({:append_attributes, attrs}, state) do
    attributes =
      Enum.reduce(attrs, state.attributes, fn {key, val}, acc ->
        Map.update(acc, key, [val], &[val | &1])
      end)

    {:noreply, %{state | attributes: attributes}}
  end

  def handle_cast({:spawn, _parent, _child, timestamp}, %{start_time: start_time} = state)
      when timestamp < start_time do
    {:noreply, state}
  end

  def handle_cast({:spawn, parent, child, timestamp}, state) do
    Process.monitor(child)
    spawn = {child, timestamp, parent, NewRelic.Util.process_name(child)}

    {:noreply,
     %{
       state
       | attributes: Map.update(state.attributes, :process_spawns, [spawn], &[spawn | &1]),
         offspring: MapSet.put(state.offspring, child)
     }}
  end

  def handle_cast({:offspring, child}, state) do
    {:noreply, %{state | offspring: MapSet.put(state.offspring, child)}}
  end

  def handle_cast({:exclude, pid}, state) do
    cleanup(lookup: pid)
    {:noreply, %{state | exclusions: [pid | state.exclusions]}}
  end

  def handle_cast(:ignore, state) do
    cleanup(context: self())
    cleanup(lookup: state.parent)
    Enum.each(state.offspring, &cleanup(lookup: &1))
    {:stop, :normal, state}
  end

  def handle_cast(:complete, state) do
    {:noreply, state, {:continue, :complete}}
  end

  def handle_info(
        {:DOWN, _, _, parent, down_reason},
        %{type: :other, parent: parent} = state
      ) do
    end_time_mono = System.monotonic_time()

    down_reason =
      case down_reason do
        {{exception, inner_stacktrace}, _initial_call} -> {exception, inner_stacktrace}
        {exception, stacktrace} -> {exception, stacktrace}
        reason -> reason
      end

    attributes =
      with {reason, stack} when reason != :shutdown <- down_reason,
           false <- match?(%{expected: true}, reason) do
        Map.put(state.attributes, :transaction_error, {:error, %{kind: :exit, reason: reason, stack: stack}})
      else
        _ -> state.attributes
      end
      |> Map.put_new(:end_time_mono, end_time_mono)

    {:noreply, %{state | attributes: attributes}, {:continue, :complete}}
  end

  def handle_info({:DOWN, _, _, child, _}, state) do
    p_exit = {child, System.system_time(:millisecond)}

    {:noreply,
     %{
       state
       | attributes: Map.update(state.attributes, :process_exits, [p_exit], &[p_exit | &1])
     }}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  def handle_continue(:complete, state) do
    cleanup(context: self())
    cleanup(lookup: state.parent)
    Enum.each(state.offspring, &cleanup(lookup: &1))
    run_complete(state)
    counter(:sub)
    report_stats()
    {:stop, :normal, :completed}
  end

  @kb 1024
  defp report_stats() do
    info = Process.info(self(), [:memory, :reductions])

    NewRelic.report_metric(
      {:supportability, :agent, "Sidecar/Process/MemoryKb"},
      value: info[:memory] / @kb
    )

    NewRelic.report_metric(
      {:supportability, :agent, "Sidecar/Process/Reductions"},
      value: info[:reductions]
    )
  end

  defp clear_sidecar() do
    Process.delete(:nr_tx_sidecar)
  end

  defp set_sidecar(pid) do
    Process.put(:nr_tx_sidecar, pid)
    pid
  end

  def get_sidecar() do
    case Process.get(:nr_tx_sidecar) do
      nil ->
        with {:links, links} <- Process.info(self(), :links),
             sidecar when is_pid(sidecar) <-
               lookup_sidecar_in(linked_process_callers(links)) ||
                 lookup_sidecar_in(linked_process_ancestors(links)) do
          cast(sidecar, {:offspring, self()})
          store_sidecar(self(), sidecar)
          set_sidecar(sidecar)
        end

      :no_track ->
        nil

      sidecar ->
        sidecar
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

  defp linked_process_callers(links) do
    for pid <- Process.get(:"$callers", []) |> Enum.reverse(),
        ^pid <- links do
      pid
    end
  end

  defp linked_process_ancestors(links) do
    for pid <- Process.get(:"$ancestors", []),
        ^pid <- links do
      pid
    end
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
    |> process_exclusions(state.exclusions)
    |> NewRelic.Transaction.Complete.run(state.parent)
  end

  defp process_exclusions(attributes, exclusions) do
    attributes
    |> Map.update(:process_spawns, [], fn spawns ->
      Enum.reject(spawns, fn {pid, _, _, _} -> pid in exclusions end)
    end)
  end
end
