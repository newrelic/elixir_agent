defmodule NewRelic.Transaction.Sidecar do
  @moduledoc false
  use GenServer, restart: :temporary

  alias NewRelic.Transaction.SidecarSupervisor

  def start_link(pid: pid) do
    GenServer.start_link(__MODULE__, pid)
  end

  def init(parent) do
    Process.monitor(parent)
    send(parent, :sidecar_ready)

    {:ok,
     %{
       parent: parent,
       offspring: MapSet.new(),
       attributes: [],
       store: %{}
     }}
  end

  def track() do
    {:ok, sidecar} =
      DynamicSupervisor.start_child(
        SidecarSupervisor,
        {__MODULE__, pid: self()}
      )

    set_sidecar(sidecar)

    receive do
      :sidecar_ready -> :ok
    end
  end

  def tracking?() do
    get_sidecar() != nil
  end

  def track_spawn(parent, child, timestamp) do
    cast(parent, {:spawn, parent, child, timestamp})
  end

  def add(attrs) do
    cast({:add_attributes, attrs})
  end

  def add(pid, attrs) do
    cast(pid, {:add_attributes, attrs})
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

  def context(context) do
    call({:set, :context, context})
  end

  def context() do
    call({:get, :context})
    |> case do
      {:error, :no_sidecar} -> nil
      context -> context
    end
  end

  def ignore() do
    call(:ignore)
  end

  def complete() do
    call(:complete)
  end

  def dump() do
    call(:dump)
  end

  defp wrap(attrs, tag) do
    Enum.map(attrs, fn {key, value} -> {key, {tag, value}} end)
  end

  defp cast(message) do
    GenServer.cast(get_sidecar(), message)
  end

  defp cast(pid, message) do
    GenServer.cast(get_sidecar(pid), message)
  end

  defp call(message) do
    GenServer.call(get_sidecar(), message)
  catch
    :exit, {:noproc, {GenServer, :call, _args}} ->
      {:error, :no_sidecar}
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

  def handle_call(:ignore, _from, state) do
    {:stop, :normal, :ok, state}
  end

  def handle_call(:complete, _from, state) do
    run_complete(state)

    {:stop, :normal, :ok, state}
  end

  def handle_info({:DOWN, _, _, parent, down_reason}, %{parent: parent} = state) do
    attributes = state.attributes

    attributes =
      with {reason, stack} when reason != :shutdown <- down_reason do
        error_attrs = [
          error: true,
          error_kind: :error,
          error_reason: inspect(reason),
          error_stack: inspect(stack)
        ]

        error_attrs ++ attributes
      else
        _ -> attributes
      end

    attributes = Keyword.put_new(attributes, :end_time_mono, System.system_time(:millisecond))

    {:noreply, %{state | attributes: attributes}, {:continue, :complete}}
  end

  def handle_info({:DOWN, _, _, child, _}, state) do
    exit_attrs = [trace_process_exits: {:list, {child, System.system_time(:millisecond)}}]

    {:noreply, %{state | attributes: exit_attrs ++ state.attributes}}
  end

  def handle_continue(:complete, state) do
    run_complete(state)

    {:stop, :normal, :completed}
  end

  defp set_sidecar(nil), do: nil

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

        IO.puts("LOOKUP_SIDECAR(#{inspect self()}) = #{inspect(sidecar)}")
        set_sidecar(sidecar)

      :no_track ->
        nil

      pid ->
        pid
    end
  end

  defp get_sidecar(pid) do
    with {:dictionary, dictionary} <- Process.info(pid, :dictionary) do
      Keyword.get(dictionary, :nr_tx_sidecar) ||
        lookup_sidecar_in(process_callers(dictionary)) ||
        lookup_sidecar_in(process_ancestors(dictionary))
    end
  end

  defp lookup_sidecar_in(processes) do
    Enum.find_value(processes, &lookup_sidecar/1)
  end

  defp lookup_sidecar(pid) when is_pid(pid) do
    with {:dictionary, dictionary} <- Process.info(pid, :dictionary) do
      case Keyword.get(dictionary, :nr_tx_sidecar) do
        nil -> nil
        :no_track -> nil
        sidecar -> sidecar
      end
    end
  end

  defp lookup_sidecar(_named_process), do: nil

  defp process_callers(),
    do: Process.get(:"$callers", []) |> Enum.reverse()

  defp process_callers(dictionary),
    do: Keyword.get(dictionary, :"$callers", []) |> Enum.reverse()

  defp process_ancestors(),
    do: Process.get(:"$ancestors", []) |> Enum.reverse()

  defp process_ancestors(dictionary),
    do: Keyword.get(dictionary, :"$ancestors", []) |> Enum.reverse()

  defp run_complete(%{parent: parent, attributes: attributes}) do
    attributes
    |> Enum.reverse()
    |> Enum.reduce(%{}, &collect_attr/2)
    |> NewRelic.Transaction.Complete.run(parent)
  end

  defp collect_attr({k, {:list, item}}, acc), do: Map.update(acc, k, [item], &[item | &1])
  defp collect_attr({k, {:counter, n}}, acc), do: Map.update(acc, k, n, &(&1 + n))
  defp collect_attr({k, v}, acc), do: Map.put(acc, k, v)
end
