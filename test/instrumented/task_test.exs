defmodule InstrumentedTaskTest do
  use ExUnit.Case

  alias NewRelic.Harvest.TelemetrySdk

  setup do
    TestHelper.simulate_agent_run(trace_mode: :infinite)
    :ok
  end

  describe "Task" do
    test "Task.async_stream/2" do
      TestHelper.restart_harvest_cycle(TelemetrySdk.Spans.HarvestCycle)

      Task.async(fn ->
        NewRelic.start_transaction("Test", "Task.async_stream")

        Task.async_stream(
          [1, 2],
          fn n ->
            NewRelic.incr_attributes(not_instrumented: n)
          end
        )
        |> Enum.map(& &1)

        alias NewRelic.Instrumented.Task

        Task.async_stream(
          [1, 2],
          fn n ->
            NewRelic.incr_attributes(instrumented: n)
          end
        )
        |> Enum.map(& &1)

        Task.async_stream(
          [1, 2],
          fn n ->
            NewRelic.incr_attributes(instrumented: n)
          end,
          ordered: false
        )
        |> Enum.map(& &1)

        Task.async_stream([1, 2], __MODULE__, :do_task, [:via_mfa])
        |> Enum.map(& &1)

        Task.async_stream([1, 2], __MODULE__, :do_task, [:via_mfa_opt], ordered: false)
        |> Enum.map(& &1)
      end)
      |> Task.await()

      [%{spans: spans}] = TestHelper.gather_harvest(TelemetrySdk.Spans.Harvester)

      spansaction =
        Enum.find(spans, fn %{attributes: attr} ->
          attr[:"nr.entryPoint"] == true
        end)

      refute spansaction.attributes[:not_instrumented]
      assert spansaction.attributes[:instrumented] == 6
      assert spansaction.attributes[:via_mfa] == 3
      assert spansaction.attributes[:via_mfa_opt] == 3
    end

    test "Task.start" do
      TestHelper.restart_harvest_cycle(TelemetrySdk.Spans.HarvestCycle)

      Task.async(fn ->
        NewRelic.start_transaction("Test", "Task.async_stream")
        pid = self()

        Task.start(fn ->
          NewRelic.add_attributes(not_instrumented: "check")
          send(pid, :next)
        end)

        assert_receive :next

        alias NewRelic.Instrumented.Task

        Task.start(fn ->
          NewRelic.add_attributes(instrumented: "check")
          send(pid, :next)
        end)

        assert_receive :next

        Task.start(__MODULE__, :do_task, [:via_mfa])
        Process.sleep(100)
      end)
      |> Task.await()

      [%{spans: spans}] = TestHelper.gather_harvest(TelemetrySdk.Spans.Harvester)

      spansaction =
        Enum.find(spans, fn %{attributes: attr} ->
          attr[:"nr.entryPoint"] == true
        end)

      refute spansaction.attributes[:not_instrumented]
      assert spansaction.attributes[:instrumented] == "check"
      assert spansaction.attributes[:via_mfa] == "check"
    end
  end

  def add_attribute_instrumented_check() do
    NewRelic.add_attributes(instrumented: "check")
  end

  describe "Task.Supervisor" do
    test "Task.Supervisor.async_nolink" do
      TestHelper.restart_harvest_cycle(TelemetrySdk.Spans.HarvestCycle)
      {:ok, _sup} = Task.Supervisor.start_link(name: TestTaskSup)

      Task.async(fn ->
        NewRelic.start_transaction("Test", "Task.Supervisor.async_nolink")

        Task.Supervisor.async_nolink(
          TestTaskSup,
          fn ->
            NewRelic.add_attributes(not_instrumented: "check")
          end
        )
        |> Task.await()

        alias NewRelic.Instrumented.Task

        Task.Supervisor.async_nolink(
          TestTaskSup,
          &add_attribute_instrumented_check/0
        )
        |> Task.await()

        Task.Supervisor.async_nolink(
          TestTaskSup,
          fn ->
            NewRelic.add_attributes(instrumented_w_opts: "check")
          end,
          shutdown: 1000
        )
        |> Task.await()

        Task.Supervisor.async_nolink(TestTaskSup, __MODULE__, :do_task, [:via_mfa])
        |> Task.await()

        Task.Supervisor.async_nolink(TestTaskSup, __MODULE__, :do_task, [:via_mfa_opt], shutdown: 1000)
        |> Task.await()
      end)
      |> Task.await()

      [%{spans: spans}] = TestHelper.gather_harvest(TelemetrySdk.Spans.Harvester)

      spansaction =
        Enum.find(spans, fn %{attributes: attr} ->
          attr[:"nr.entryPoint"] == true
        end)

      refute spansaction.attributes[:not_instrumented]
      assert spansaction.attributes[:instrumented] == "check"
      assert spansaction.attributes[:instrumented_w_opts] == "check"
      assert spansaction.attributes[:via_mfa] == "check"
      assert spansaction.attributes[:via_mfa_opt] == "check"
    end

    def do_task(attr) do
      NewRelic.add_attributes([{attr, "check"}])
    end

    def do_task(n, attr) do
      NewRelic.incr_attributes([{attr, n}])
    end

    test "Task.Supervisor.start_child" do
      TestHelper.restart_harvest_cycle(TelemetrySdk.Spans.HarvestCycle)
      {:ok, _sup} = Task.Supervisor.start_link(name: TestTaskSup)

      Task.async(fn ->
        NewRelic.start_transaction("Test", "Task.Supervisor.start_child")
        pid = self()

        Task.Supervisor.start_child(
          TestTaskSup,
          fn ->
            NewRelic.add_attributes(not_instrumented: "check")
            send(pid, :next)
          end
        )

        assert_receive :next

        alias NewRelic.Instrumented.Task

        Task.Supervisor.start_child(
          TestTaskSup,
          fn ->
            NewRelic.add_attributes(instrumented: "check")
            send(pid, :next)
          end
        )

        assert_receive :next

        Task.Supervisor.start_child(
          TestTaskSup,
          fn ->
            NewRelic.add_attributes(instrumented_w_opts: "check")
            send(pid, :next)
          end,
          shutdown: 1000
        )

        Task.Supervisor.start_child(
          TestTaskSup,
          __MODULE__,
          :do_task,
          [:via_mfa]
        )

        Task.Supervisor.start_child(
          TestTaskSup,
          __MODULE__,
          :do_task,
          [:via_mfa_opt],
          shutdown: 1000
        )

        Process.sleep(100)

        assert_receive :next
      end)
      |> Task.await()

      [%{spans: spans}] = TestHelper.gather_harvest(TelemetrySdk.Spans.Harvester)

      spansaction =
        Enum.find(spans, fn %{attributes: attr} ->
          attr[:"nr.entryPoint"] == true
        end)

      refute spansaction.attributes[:not_instrumented]
      assert spansaction.attributes[:instrumented] == "check"
      assert spansaction.attributes[:instrumented_w_opts] == "check"
      assert spansaction.attributes[:via_mfa] == "check"
      assert spansaction.attributes[:via_mfa_opt] == "check"
    end

    test "Task.Supervisor.async_stream_nolink" do
      TestHelper.restart_harvest_cycle(TelemetrySdk.Spans.HarvestCycle)
      {:ok, _sup} = Task.Supervisor.start_link(name: TestTaskSup)

      Task.async(fn ->
        NewRelic.start_transaction("Test", "Task.Supervisor.async_stream_nolink")

        Task.Supervisor.async_stream_nolink(
          TestTaskSup,
          [1, 2],
          fn n ->
            NewRelic.incr_attributes(not_instrumented: n)
          end
        )
        |> Enum.map(& &1)

        alias NewRelic.Instrumented.Task

        Task.Supervisor.async_stream_nolink(
          TestTaskSup,
          [1, 2],
          fn n ->
            NewRelic.incr_attributes(instrumented: n)
          end
        )
        |> Enum.map(& &1)

        Task.Supervisor.async_stream_nolink(
          TestTaskSup,
          [1, 2],
          fn n ->
            NewRelic.incr_attributes(instrumented_w_opts: n)
          end,
          ordered: false
        )
        |> Enum.map(& &1)

        Task.Supervisor.async_stream_nolink(
          TestTaskSup,
          [1, 2],
          __MODULE__,
          :do_task,
          [:via_mfa]
        )
        |> Enum.map(& &1)

        Task.Supervisor.async_stream_nolink(
          TestTaskSup,
          [1, 2],
          __MODULE__,
          :do_task,
          [:via_mfa_opt],
          ordered: false
        )
        |> Enum.map(& &1)
      end)
      |> Task.await()

      [%{spans: spans}] = TestHelper.gather_harvest(TelemetrySdk.Spans.Harvester)

      spansaction =
        Enum.find(spans, fn %{attributes: attr} ->
          attr[:"nr.entryPoint"] == true
        end)

      refute spansaction.attributes[:not_instrumented]
      assert spansaction.attributes[:instrumented] == 3
      assert spansaction.attributes[:instrumented_w_opts] == 3
      assert spansaction.attributes[:via_mfa] == 3
      assert spansaction.attributes[:via_mfa_opt] == 3
    end

    test "Task.Supervisor.async_stream" do
      TestHelper.restart_harvest_cycle(TelemetrySdk.Spans.HarvestCycle)
      {:ok, _sup} = Task.Supervisor.start_link(name: TestTaskSup)

      Task.async(fn ->
        NewRelic.start_transaction("Test", "Task.Supervisor.async_stream_nolink")

        Task.Supervisor.async_stream(
          TestTaskSup,
          [1, 2],
          fn n ->
            NewRelic.incr_attributes(not_instrumented: n)
          end
        )
        |> Enum.map(& &1)

        alias NewRelic.Instrumented.Task

        Task.Supervisor.async_stream(
          TestTaskSup,
          [1, 2],
          fn n ->
            NewRelic.incr_attributes(instrumented: n)
          end
        )
        |> Enum.map(& &1)

        Task.Supervisor.async_stream(
          TestTaskSup,
          [1, 2],
          fn n ->
            NewRelic.incr_attributes(instrumented_w_opts: n)
          end,
          ordered: false
        )
        |> Enum.map(& &1)

        Task.Supervisor.async_stream(
          TestTaskSup,
          [1, 2],
          __MODULE__,
          :do_task,
          [:via_mfa_opt],
          ordered: false
        )
        |> Enum.map(& &1)
      end)
      |> Task.await()

      [%{spans: spans}] = TestHelper.gather_harvest(TelemetrySdk.Spans.Harvester)

      spansaction =
        Enum.find(spans, fn %{attributes: attr} ->
          attr[:"nr.entryPoint"] == true
        end)

      refute spansaction.attributes[:not_instrumented]
      assert spansaction.attributes[:instrumented] == 3
      assert spansaction.attributes[:instrumented_w_opts] == 3
      assert spansaction.attributes[:via_mfa_opt] == 3
    end

    test "Task.Supervisor.async is just delegated" do
      TestHelper.restart_harvest_cycle(TelemetrySdk.Spans.HarvestCycle)
      {:ok, _sup} = Task.Supervisor.start_link(name: TestTaskSup)

      Task.async(fn ->
        NewRelic.start_transaction("Test", "Task.async")

        alias NewRelic.Instrumented.Task

        Task.Supervisor.async(TestTaskSup, fn ->
          NewRelic.add_attributes(instrumented: "check")
        end)
        |> Task.await()
      end)
      |> Task.await()

      [%{spans: spans}] = TestHelper.gather_harvest(TelemetrySdk.Spans.Harvester)

      spansaction =
        Enum.find(spans, fn %{attributes: attr} ->
          attr[:"nr.entryPoint"] == true
        end)

      refute spansaction.attributes[:not_instrumented]
      assert spansaction.attributes[:instrumented] == "check"
    end
  end
end
