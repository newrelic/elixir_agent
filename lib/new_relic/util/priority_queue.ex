defmodule NewRelic.Util.PriorityQueue do
  # This is a simple PriorityQueue based on erlang's gb_trees used to
  # keep the highest priority events when we reach max harvest size

  @moduledoc false

  def new() do
    :gb_trees.empty()
  end

  def insert(tree, max_size, key, value) do
    insert(tree, :gb_trees.size(tree), max_size, key, value)
  end

  def insert(tree, size, max_size, key, value) when size >= max_size do
    {_k, _v, tree} =
      {key, differentiator()}
      |> :gb_trees.insert(value, tree)
      |> :gb_trees.take_smallest()

    tree
  end

  def insert(tree, _size, _max_size, key, value) do
    {key, differentiator()}
    |> :gb_trees.insert(value, tree)
  end

  def values(tree) do
    :gb_trees.values(tree)
  end

  defp differentiator() do
    :erlang.unique_integer()
  end
end
