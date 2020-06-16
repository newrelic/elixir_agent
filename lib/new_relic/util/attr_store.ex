defmodule NewRelic.Util.AttrStore do
  # This is an abstraction around ETS that lets us store efficently
  # store and access arbitrary key->value pairs for all Transactions we are tracking
  #
  # It is backed by two ETS tables:
  # 1) tracking all processes involved in a Transaction
  # 2) collecting attributes stored on a Transaction

  @moduledoc false

  @ets_options [:named_table, :duplicate_bag, :public]
  def new(table) do
    :ets.new(collecting(table), @ets_options ++ [write_concurrency: true])
    :ets.new(tracking(table), @ets_options ++ [read_concurrency: true, write_concurrency: true])
  end

  def track(table, pid) do
    insert(
      tracking(table),
      {{pid, :tracking}, true}
    )
  end

  def link(table, parent, child) do
    root = find_root(parent, table)

    insert(
      tracking(table),
      [
        {{child, :tracking}, true},
        {{child, :child_of}, root},
        {{root, :root_of}, child}
      ]
    )
  end

  def root(table, pid) do
    find_root(pid, table)
  end

  def add(table, pid, attrs) when is_list(attrs) do
    insert(
      collecting(table),
      Enum.map(attrs, fn {key, value} -> {pid, {key, value}} end)
    )
  end

  def incr(table, pid, attrs) when is_list(attrs) do
    insert(
      collecting(table),
      Enum.map(attrs, fn {key, value} -> {pid, {key, {:counter, value}}} end)
    )
  end

  def tracking?(table, pid) do
    member?(
      tracking(table),
      {pid, :tracking}
    )
  end

  def collect(table, pid) do
    pid
    |> with_children(table)
    |> find_attributes(table)
    |> Enum.reduce(%{}, &collect_attr/2)
  end

  def untrack(table, pid) do
    pid
    |> find_root(table)
    |> with_children(table)
    |> Enum.each(fn pid ->
      delete(tracking(table), {pid, :tracking})
    end)
  end

  def purge(table, pid) do
    pid
    |> find_root(table)
    |> with_children(table)
    |> Enum.each(fn pid ->
      delete(collecting(table), pid)

      delete(tracking(table), {pid, :tracking})
      delete(tracking(table), {pid, :child_of})
      delete(tracking(table), {pid, :root_of})
    end)
  end

  defp find_root(pid, table) do
    lookup(
      tracking(table),
      {pid, :child_of}
    )
    |> case do
      [{_, root} | _] -> root
      [] -> pid
    end
  end

  defp with_children(pid, table) do
    [pid | find_children(table, pid)]
  end

  defp find_children(table, root_pid) do
    lookup(
      tracking(table),
      {root_pid, :root_of}
    )
    |> Enum.map(fn {_, child} -> child end)
  end

  def find_attributes(pids, table) do
    Enum.flat_map(pids, fn pid ->
      take(
        collecting(table),
        pid
      )
    end)
  end

  def collect_attr({_pid, {k, {:list, item}}}, acc), do: Map.update(acc, k, [item], &[item | &1])
  def collect_attr({_pid, {k, {:counter, n}}}, acc), do: Map.update(acc, k, n, &(&1 + n))
  def collect_attr({_pid, {k, v}}, acc), do: Map.put(acc, k, v)

  defp collecting(table), do: Module.concat(table, Collecting)
  defp tracking(table), do: Module.concat(table, Tracking)

  defp lookup(table, term) do
    :ets.lookup(table, term)
  rescue
    ArgumentError -> []
  end

  defp take(table, term) do
    :ets.take(table, term)
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
