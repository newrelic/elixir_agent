defmodule TransactionRegistryTest do
  use ExUnit.Case

  alias NewRelic.Transaction.Store

  test "Get Transaction.Store working" do
    task =
      Task.async(fn ->
        NewRelic.start_transaction("Test", "Tx")

        NewRelic.add_attributes(foo: "BAR")

        Task.async(fn ->
          Process.sleep(10)
          NewRelic.add_attributes(baz: "QUX")
        end)
        |> Task.await()

        %{attributes: attributes} = Store.dump()

        NewRelic.stop_transaction()

        assert attributes[:foo] == "BAR"
        assert attributes[:baz] == "QUX"
      end)

    Task.await(task)

    Process.sleep(200)
    assert 0 == Registry.count(NewRelic.Transaction.Registry)
  end
end
