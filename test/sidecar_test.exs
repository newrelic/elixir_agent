defmodule SidecarTest do
  use ExUnit.Case

  test "Transaction.Sidecar" do
    Task.async(fn ->
      NewRelic.start_transaction("Test", "Tx")
      NewRelic.add_attributes(foo: "BAR")

      Task.async(fn ->
        NewRelic.add_attributes(baz: "QUX")

        Task.async(fn ->
          NewRelic.add_attributes(blah: "BLAH")

          Task.async(fn ->
            NewRelic.add_attributes(deep: "DEEP")
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
    |> Task.await()
  end

end
