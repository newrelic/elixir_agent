defmodule NewRelic.Util.AttrStore do
  # This is an abstraction around an ETS table that lets us store efficently
  # store and access arbitrary key->value pairs for all Transactions we are tracking

  @moduledoc false

  def new(table) do
    :ets.new(table, [
      :named_table,
      :duplicate_bag,
      :public,
      read_concurrency: true,
      write_concurrency: true
    ])
  end

  def track(table, pid) do
    insert(table, {{pid, :tracking}, true})
  end

  def link(table, parent, child, attrs \\ []) do
    root = find_root(table, parent)
    extras = Enum.map(attrs, fn {key, value} -> {child, {key, value}} end)

    insert(table, [
      {{child, :tracking}, true},
      {{child, :child_of}, root},
      {{root, :root_of}, child} | extras
    ])
  end

  def add(table, pid, attrs)
      when is_list(attrs) do
    items = Enum.map(attrs, fn {key, value} -> {pid, {key, value}} end)
    insert(table, items)
  end

  def incr(table, pid, attrs)
      when is_list(attrs) do
    items = Enum.map(attrs, fn {key, value} -> {pid, {key, {:counter, value}}} end)
    insert(table, items)
  end

  def tracking?(table, pid) do
    member?(table, {pid, :tracking})
  end

  def collect(table, pid) do
    pids = [pid | find_children(table, pid)]

    table
    |> find_attributes(pids)
    |> Enum.reduce(%{}, &collect_attr/2)
  end

  def untrack(table, pid) do
    delete(table, {pid, :tracking})
  end

  def purge(table, pid) do
    [pid | find_children(table, pid)]
    |> Enum.each(fn pid ->
      delete(table, pid)
      delete(table, {pid, :tracking})
      delete(table, {pid, :child_of})
      delete(table, {pid, :root_of})
    end)
  end

  def find_root(table, pid) do
    lookup(table, {pid, :child_of})
    |> case do
      [{_, root} | _] -> root
      [] -> pid
    end
  end

  def find_children(table, root_pid) do
    lookup(table, {root_pid, :root_of})
    |> Enum.map(fn {_, child} -> child end)
  end

  def find_attributes(table, pids) do
    Enum.flat_map(pids, fn pid ->
      lookup(table, pid)
    end)
  end

  @immutable_keys [:framework_name]
  defp collect_attr({_pid, {k, {:list, item}}}, acc), do: Map.update(acc, k, [item], &[item | &1])
  defp collect_attr({_pid, {k, {:counter, n}}}, acc), do: Map.update(acc, k, n, &(&1 + n))
  defp collect_attr({_pid, {k, v}}, acc) when k in @immutable_keys, do: Map.put_new(acc, k, v)
  defp collect_attr({_pid, {k, v}}, acc), do: Map.put(acc, k, v)

  defp lookup(table, term) do
    :ets.lookup(table, term)
  rescue
    ArgumentError -> []
  end

  defp insert(table, term) do
    :ets.insert(table, term)
  rescue
    ArgumentError -> false
  end

  defp delete(table, term) do
    :ets.delete(table, term)
  rescue
    ArgumentError -> false
  end

  defp member?(table, term) do
    :ets.member(table, term)
  rescue
    ArgumentError -> false
  end
end
