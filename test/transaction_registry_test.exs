defmodule TransactionRegistryTest do
  use ExUnit.Case

  alias NewRelic.Transaction.Store

  test "asdofkj" do
    task =
      Task.async(fn ->
        parent = self()
        Store.new()

        Store.add_attributes(foo: :BAR)

        Task.async(fn ->
          # Do this from Transaction.Monitor!
          child = self()
          NewRelic.Transaction.Store.link(parent, child)

          Store.add_attributes(baz: :QUX)
        end)
        |> Task.await()

        %{attributes: attributes} = Store.dump()

        assert attributes[:foo] == :BAR
        assert attributes[:baz] == :QUX
      end)

    Task.await(task)

    Process.sleep(200)
    assert 0 == Registry.count(NewRelic.Transaction.Registry)
  end
end
