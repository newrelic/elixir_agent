defmodule OtherTransactionTest do
  use ExUnit.Case
  alias NewRelic.Harvest.Collector

  test "works" do
    TestHelper.restart_harvest_cycle(Collector.TransactionEvent.HarvestCycle)

    Task.async(fn ->
      NewRelic.start_transaction("TransactionCategory", "MyTaskName")
      NewRelic.add_attributes(other: "transaction")
    end)
    |> Task.await()

    [event] = TestHelper.gather_harvest(Collector.TransactionEvent.Harvester)
    [%{name: name}, %{other: "transaction"}] = event

    assert name == "OtherTransaction/TransactionCategory/MyTaskName"

    TestHelper.pause_harvest_cycle(Collector.TransactionEvent.HarvestCycle)
  end
end
