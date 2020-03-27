defmodule AttrStoreTest do
  use ExUnit.Case
  alias NewRelic.Util.AttrStore

  test "AttrStore map accumulator via ETS" do
    table = AttrStore.Test
    AttrStore.new(table)

    AttrStore.track(table, :pid)
    AttrStore.add(table, :pid, name: "FOO")
    AttrStore.add(table, :pid, route: "/foo")
    AttrStore.add(table, :pid, bar: "baz")
    AttrStore.add(table, :pid, bar: "baz")
    AttrStore.add(table, :pid, this: "this", that: "that")

    AttrStore.add(table, :pid, count_tag: {:counter, 1})
    AttrStore.add(table, :pid, count_tag: {:counter, 1})
    AttrStore.add(table, :pid, err_key: {:error, "tagged value"})

    AttrStore.incr(table, :pid, seven: 3)
    AttrStore.incr(table, :pid, seven: 4.0)
    AttrStore.incr(table, :pid, one: 1, two: 2)

    attrs = AttrStore.collect(table, :pid)

    assert Enum.member?(attrs, {:bar, "baz"})
    assert Enum.member?(attrs, {:this, "this"})
    assert Enum.member?(attrs, {:that, "that"})
    assert Enum.member?(attrs, {:seven, 7.0})
    assert Enum.member?(attrs, {:one, 1})
    assert Enum.member?(attrs, {:two, 2})
    assert Enum.member?(attrs, {:count_tag, 2})

    assert %{} == AttrStore.collect(table, :pid)
  end

  test "Track a spawned child with parent PID" do
    table = AttrStore.Test
    AttrStore.new(table)

    AttrStore.track(table, :pid)
    AttrStore.link(table, :pid, :task)

    links = AttrStore.find_children(table, :pid)
    assert links == [:task]

    assert [] == AttrStore.find_children(table, :not_there)

    AttrStore.add(table, :pid, foo: "BAR")
    AttrStore.add(table, :task, baz: "QUX")

    AttrStore.untrack(table, :pid)
    attrs = AttrStore.collect(table, :pid)
    assert attrs == %{foo: "BAR", baz: "QUX"}

    refute AttrStore.tracking?(table, :pid)
    assert %{} == AttrStore.collect(table, :task)
    assert %{} == AttrStore.collect(table, :pid)
  end

  test "Purge deletes attrs for links" do
    table = AttrStore.Test
    AttrStore.new(table)

    AttrStore.track(table, :pid)
    AttrStore.link(table, :pid, :task)

    AttrStore.add(table, :pid, foo: "BAR")
    AttrStore.add(table, :task, baz: "QUX")

    assert :ok == AttrStore.purge(table, :pid)
    assert %{} == AttrStore.collect(table, :task)
  end

  test "Track deeply nested spawned child" do
    table = AttrStore.Test
    AttrStore.new(table)

    AttrStore.track(table, :pid)
    AttrStore.link(table, :pid, :task)
    AttrStore.link(table, :task, :another_task)
    AttrStore.link(table, :task, :sibling_task)
    AttrStore.link(table, :another_task, :super_nested)

    links = AttrStore.find_children(table, :pid)
    assert [] = links -- [:task, :another_task, :super_nested, :sibling_task]

    assert AttrStore.find_root(table, :pid) == :pid
    assert AttrStore.find_root(table, :task) == :pid
    assert AttrStore.find_root(table, :another_task) == :pid
    assert AttrStore.find_root(table, :sibling_task) == :pid
    assert AttrStore.find_root(table, :super_nested) == :pid

    AttrStore.add(table, :pid, grand: "PARENT")
    AttrStore.add(table, :task, foo: "BAR")
    AttrStore.add(table, :another_task, baz: "QUX")
    AttrStore.add(table, :sibling_task, sibling: "ANOTHER_TASK")
    AttrStore.add(table, :super_nested, crazy: "STUFF")

    attrs = AttrStore.collect(table, :pid)

    assert attrs == %{
             grand: "PARENT",
             foo: "BAR",
             baz: "QUX",
             sibling: "ANOTHER_TASK",
             crazy: "STUFF"
           }
  end

  test "Check if a process is being tracked" do
    table = AttrStore.Test
    AttrStore.new(table)

    AttrStore.track(table, :pid)
    AttrStore.track(table, :pid2)

    AttrStore.link(table, :pid, :task1)
    AttrStore.link(table, :task1, :task2)
    AttrStore.link(table, :task2, :task3)

    assert AttrStore.tracking?(table, :pid)
    assert AttrStore.tracking?(table, :pid2)
    assert AttrStore.tracking?(table, :task2)
    assert AttrStore.tracking?(table, :task3)
    refute AttrStore.tracking?(table, :pidddd)

    assert AttrStore.tracking?(table, :pid)
    AttrStore.untrack(table, :pid)
    refute AttrStore.tracking?(table, :pid)
    refute AttrStore.tracking?(table, :task1)
    refute AttrStore.tracking?(table, :task2)
    refute AttrStore.tracking?(table, :task3)
  end

  test "If the table doesn't exist, don't blow up" do
    AttrStore.track(NoTable, :pid)
    AttrStore.add(NoTable, :pid, some: "VALUE")
    AttrStore.tracking?(NoTable, self())
    AttrStore.find_root(NoTable, self())
    AttrStore.purge(NoTable, self())
  end
end
