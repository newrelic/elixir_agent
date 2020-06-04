defmodule TransactionRegistryTest do
  use ExUnit.Case

  test "Get Transaction.Sidecar working" do
    task =
      Task.async(fn ->
        NewRelic.start_transaction("Test", "Tx")
        NewRelic.add_attributes(foo: "BAR")

        Task.async(fn ->
          Process.sleep(10)
          NewRelic.add_attributes(baz: "QUX")

          Task.async(fn ->
            Process.sleep(10)
            NewRelic.add_attributes(blah: "BLAH")

            Task.async(fn ->
              Process.sleep(10)
              NewRelic.add_attributes(deep: "DEEP")

              assert 4 == Registry.count(NewRelic.Transaction.Registry)
            end)
            |> Task.await()
          end)
          |> Task.await()
        end)
        |> Task.await()

        %{attributes: attributes} = NewRelic.Transaction.Sidecar.dump()

        NewRelic.stop_transaction()

        assert attributes[:foo] == "BAR"
        assert attributes[:baz] == "QUX"
        assert attributes[:blah] == "BLAH"
        assert attributes[:deep] == "DEEP"
      end)

    Task.await(task)

    Process.sleep(200)
    assert 0 == Registry.count(NewRelic.Transaction.Registry)
  end
end
