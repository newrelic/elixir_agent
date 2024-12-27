defmodule SidecarTest do
  use ExUnit.Case

  alias NewRelic.Transaction.Sidecar
  alias NewRelic.Harvest.Collector
  alias NewRelic.Harvest.TelemetrySdk

  setup do
    reset_agent_run = TestHelper.update(:nr_agent_run, trusted_account_key: "190")

    reset_config =
      TestHelper.update(:nr_config,
        license_key: "dummy_key",
        harvest_enabled: true,
        trace_mode: :infinite,
        automatic_attributes: %{auto: "attribute"}
      )

    on_exit(fn ->
      reset_agent_run.()
      reset_config.()
    end)

    :ok
  end

  defmodule SimpleServer do
    use GenServer

    def init(:ok) do
      NewRelic.add_attributes(gen_server: "init")
      {:ok, nil}
    end
  end

  test "Transaction.Sidecar" do
    TestHelper.restart_harvest_cycle(Collector.Metric.HarvestCycle)

    Task.async(fn ->
      NewRelic.start_transaction("Test", "Tx")
      NewRelic.add_attributes(foo: "BAR")

      Task.async(fn ->
        NewRelic.add_attributes(baz: "QUX")
        GenServer.start_link(SimpleServer, :ok)

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
      assert attributes[:gen_server] == "init"

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

      tx = NewRelic.get_transaction()

      pid =
        spawn(fn ->
          NewRelic.connect_to_transaction(tx)
          NewRelic.add_attributes(foo2: "BAZ")

          assert :ets.member(Sidecar.LookupStore, self())

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

      refute :ets.member(Sidecar.LookupStore, pid)
    end)
    |> Task.await()
  end

  defmodule Traced do
    use NewRelic.Tracer

    @trace :hey
    def hey do
      :hey
    end

    @trace :hello
    def hello do
      :hello
    end

    @trace :instrumented_task_async_nolink
    def instrumented_task_async_nolink(fun) do
      alias NewRelic.Instrumented.Task

      Task.Supervisor.async_nolink(TestTaskSup, fun)
      |> Task.await()
    end
  end

  test "manually connect Task nolink processes" do
    TestHelper.restart_harvest_cycle(TelemetrySdk.Spans.HarvestCycle)
    {:ok, _sup} = Task.Supervisor.start_link(name: TestTaskSup)
    test = self()

    spawn(fn ->
      NewRelic.start_transaction("Test", "manual_nolink_connection")
      NewRelic.add_attributes(root: :YES)

      Task.Supervisor.async_nolink(
        TestTaskSup,
        fn ->
          NewRelic.add_attributes(async_nolink: :NO)
        end
      )
      |> Task.await()

      Traced.instrumented_task_async_nolink(fn ->
        NewRelic.add_attributes(async_nolink_connected: :YES)
        Traced.hey()

        NewRelic.Instrumented.Task.Supervisor.async_stream_nolink(
          TestTaskSup,
          [:YES],
          fn val ->
            NewRelic.add_attributes(async_stream_nolink_connected: val)
            Traced.hello()
          end
        )
        |> Enum.map(& &1)
      end)

      send(test, :done)
    end)

    receive do
      :done -> :ok
    end

    [%{spans: spans}] = TestHelper.gather_harvest(TelemetrySdk.Spans.Harvester)

    spansaction =
      Enum.find(spans, fn %{attributes: attr} ->
        attr[:"nr.entryPoint"] == true
      end)

    assert spansaction.attributes[:root] == "YES"
    refute spansaction.attributes[:async_nolink]
    assert spansaction.attributes[:async_nolink_connected] == "YES"
    assert spansaction.attributes[:async_stream_nolink_connected] == "YES"

    tx_root_process_span =
      Enum.find(spans, fn %{attributes: attr} ->
        attr[:name] == "Transaction Root Process"
      end)

    task_triggering_function_span =
      Enum.find(spans, fn %{attributes: attr} ->
        attr[:name] == "SidecarTest.Traced.instrumented_task_async_nolink/1"
      end)

    assert task_triggering_function_span.attributes[:"parent.id"] == tx_root_process_span[:id]

    task_triggered_process_span =
      Enum.find(spans, fn %{attributes: attr} ->
        attr[:name] == "Process" &&
          attr[:"parent.id"] == task_triggering_function_span[:id]
      end)

    hey_function_span =
      Enum.find(spans, fn %{attributes: attr} ->
        attr[:name] == "SidecarTest.Traced.hey/0"
      end)

    assert hey_function_span.attributes[:"parent.id"] == task_triggered_process_span[:id]

    connected_stream_task_process_span =
      Enum.find(spans, fn %{attributes: attr} ->
        attr[:"parent.id"] == task_triggered_process_span[:id]
      end)

    assert connected_stream_task_process_span.attributes[:name] == "Process"

    hello_function_span =
      Enum.find(spans, fn %{attributes: attr} ->
        attr[:name] == "SidecarTest.Traced.hello/0"
      end)

    assert hello_function_span.attributes[:"parent.id"] == connected_stream_task_process_span[:id]
  end

  test "No-op when manually connecting inside an existing Transaction" do
    TestHelper.restart_harvest_cycle(TelemetrySdk.Spans.HarvestCycle)
    test = self()

    t1 =
      Task.async(fn ->
        NewRelic.start_transaction("Test", "first_tx")

        send(test, {:tx, NewRelic.get_transaction()})

        receive do
          :finish -> :ok
        end
      end)

    tx =
      receive do
        {:tx, tx} -> tx
      end

    Task.async(fn ->
      NewRelic.start_transaction("Test", "double_connect_test")
      NewRelic.add_attributes(root: :YES)

      Task.async(fn ->
        # Should stay connected to parent Transaction:
        NewRelic.connect_to_transaction(tx)

        NewRelic.add_attributes(async_nolink_connected: :YES)
      end)
      |> Task.await()
    end)
    |> Task.await()

    send(t1.pid, :finish)

    [%{spans: spans}] = TestHelper.gather_harvest(TelemetrySdk.Spans.Harvester)

    spansaction =
      Enum.find(spans, fn %{attributes: attr} ->
        attr[:"nr.entryPoint"] == true && attr[:name] == "Test/double_connect_test"
      end)

    assert spansaction.attributes[:root] == "YES"
    assert spansaction.attributes[:async_nolink_connected] == "YES"
  end

  test "no-op when attempting to connect outside a Transaction" do
    tx = NewRelic.get_transaction()
    NewRelic.connect_to_transaction(tx)
  end

  test "don't leak when stop_transaction isn't called" do
    test = self()

    task =
      Task.async(fn ->
        NewRelic.start_transaction("Test", "leak")
        send(test, {:started, NewRelic.Transaction.Sidecar.get_sidecar()})

        Process.sleep(300)
      end)

    assert_receive {:started, sidecar}
    Process.monitor(sidecar)

    assert [{_, ^sidecar}] = :ets.lookup(NewRelic.Transaction.Sidecar.LookupStore, task.pid)

    Task.await(task)

    assert_receive {:DOWN, _, _, ^sidecar, _}
    assert [] = :ets.lookup(NewRelic.Transaction.Sidecar.LookupStore, task.pid)
  end
end
