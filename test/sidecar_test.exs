defmodule SidecarTest do
  use ExUnit.Case

  alias NewRelic.Transaction.Sidecar
  alias NewRelic.Harvest.Collector

  test "Transaction.Sidecar" do
    TestHelper.restart_harvest_cycle(Collector.Metric.HarvestCycle)

    Task.async(fn ->
      NewRelic.start_transaction("Test", "Tx")
      NewRelic.add_attributes(foo: "BAR")

      Task.async(fn ->
        NewRelic.add_attributes(baz: "QUX")

        Task.async(fn ->
          NewRelic.add_attributes(blah: "BLAH")
          NewRelic.add_attributes(blah2: "BLAH2")
          NewRelic.add_attributes(blah3: "BLAH3")
          NewRelic.add_attributes(blah4: "BLAH4")

          Task.async(fn ->
            NewRelic.add_attributes(deep: "DEEP")

            headers = NewRelic.distributed_trace_headers(:http)
            assert length(headers) == 3
          end)
          |> Task.await()
        end)
        |> Task.await()
      end)
      |> Task.await()

      sidecar = Process.get(:nr_tx_sidecar)

      %{attributes: attributes} = :sys.get_state(sidecar)
      assert attributes[:foo] == "BAR"
      assert attributes[:baz] == "QUX"
      assert attributes[:blah] == "BLAH"
      assert attributes[:deep] == "DEEP"

      assert :ets.member(Sidecar.ContextStore, {:context, sidecar})

      NewRelic.stop_transaction()

      refute :ets.member(Sidecar.ContextStore, {:context, sidecar})
    end)
    |> Task.await()

    metrics = TestHelper.gather_harvest(Collector.Metric.Harvester)

    assert TestHelper.find_metric(
             metrics,
             "Supportability/ElixirAgent/Sidecar/Process/MemoryKb"
           )
  end

  test "multiple transctions in a row in a process" do
    Task.async(fn ->
      # First

      NewRelic.start_transaction("Test", "Tx2")
      NewRelic.add_attributes(foo1: "BAR")

      Task.async(fn ->
        NewRelic.add_attributes(baz1: "QUX")
      end)
      |> Task.await()

      sidecar = Process.get(:nr_tx_sidecar)
      %{attributes: attributes} = :sys.get_state(sidecar)

      assert attributes[:foo1] == "BAR"
      assert attributes[:baz1] == "QUX"

      Process.sleep(30)

      assert :ets.member(Sidecar.LookupStore, self())

      NewRelic.stop_transaction()

      refute :ets.member(Sidecar.LookupStore, self())

      # Second

      NewRelic.start_transaction("Test", "Tx1")
      NewRelic.add_attributes(foo2: "BAR")

      task =
        Task.async(fn ->
          NewRelic.add_attributes(baz2: "QUX")

          # This Task will take longer than the Transaction
          Process.sleep(20)
        end)

      Process.sleep(10)

      sidecar = Process.get(:nr_tx_sidecar)
      %{attributes: attributes} = :sys.get_state(sidecar)

      refute attributes[:foo1]
      assert attributes[:foo2] == "BAR"
      assert attributes[:baz2] == "QUX"

      NewRelic.stop_transaction()

      Task.await(task)
    end)
    |> Task.await()
  end

  test "ignored transaction cleans itself up" do
    Task.async(fn ->
      Task.async(fn ->
        NewRelic.start_transaction("Test", "ignored")
        NewRelic.add_attributes(foo1: "BAR")

        assert :ets.member(Sidecar.LookupStore, self())

        NewRelic.ignore_transaction()

        # Ignored transactions get cleaned up async
        Process.sleep(10)

        refute :ets.member(Sidecar.LookupStore, self())
      end)
      |> Task.await()
    end)
    |> Task.await()
  end

  test "manually connect an individual process" do
    Task.async(fn ->
      NewRelic.start_transaction("Test", "manual_connection")
      NewRelic.add_attributes(foo1: "BAR")

      pid = self()

      spawn(fn ->
        NewRelic.connect_to_transaction(pid)
        NewRelic.add_attributes(foo2: "BAZ")

        NewRelic.disconnect_from_transaction()
        NewRelic.add_attributes(foo3: "QUX")

        send(pid, :carry_on)
      end)

      assert_receive :carry_on
      Process.sleep(500)

      assert :ets.member(Sidecar.LookupStore, self())
      sidecar = Process.get(:nr_tx_sidecar)

      %{attributes: attributes} = :sys.get_state(sidecar)
      assert attributes[:foo1] == "BAR"
      assert attributes[:foo2] == "BAZ"
      refute attributes[:foo3]
    end)
    |> Task.await()

    # no-op when called outside a Transaction
    NewRelic.connect_to_transaction(self())
  end
end
