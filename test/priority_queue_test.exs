defmodule PriorityQueueTest do
  use ExUnit.Case

  alias NewRelic.Util.PriorityQueue

  test "priority queue" do
    max = 3

    pq =
      PriorityQueue.new()
      |> PriorityQueue.insert(max, 2, :bar)
      |> PriorityQueue.insert(max, 2, :bar)
      |> PriorityQueue.insert(max, 2, :bar)
      |> PriorityQueue.insert(max, 2, :bar)
      |> PriorityQueue.insert(max, 3, :baz)
      |> PriorityQueue.insert(max, 4, :first)
      |> PriorityQueue.insert(max, 5, :second)
      |> PriorityQueue.insert(max, 5, :third)
      |> PriorityQueue.insert(max, 1, :foo)

    assert [:first, :second, :third] == PriorityQueue.values(pq)
  end
end
