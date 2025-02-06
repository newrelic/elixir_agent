defmodule ErlangTraceTest do
  use ExUnit.Case, async: false

  test "disable and re-enable Agent's usage of `:erlang.trace`" do
    first_pid = Process.whereis(NewRelic.Transaction.ErlangTrace)
    assert is_pid(first_pid)
    Process.monitor(first_pid)

    NewRelic.disable_erlang_trace()

    on_exit(fn ->
      NewRelic.enable_erlang_trace()
    end)

    assert_receive {:DOWN, _ref, _, ^first_pid, _}

    NewRelic.enable_erlang_trace()

    second_pid = Process.whereis(NewRelic.Transaction.ErlangTrace)
    assert is_pid(second_pid)
    assert first_pid != second_pid
  end

  test "config option to disable at boot" do
    restart_erlang_trace_supervisor()
    on_exit(fn -> restart_erlang_trace_supervisor() end)

    # Make sure it starts up with the default setting
    assert Process.whereis(NewRelic.Transaction.ErlangTraceSupervisor)
    assert Process.whereis(NewRelic.Transaction.ErlangTrace)

    # Pretend the app is starting up with the config option
    TestHelper.run_with(:application_config, disable_erlang_trace: true)
    restart_erlang_trace_supervisor()

    # Make sure we didn't start the ErlangTrace process
    assert Process.whereis(NewRelic.Transaction.ErlangTraceSupervisor)
    refute Process.whereis(NewRelic.Transaction.ErlangTrace)
  end

  defp restart_erlang_trace_supervisor() do
    supervisor = Process.whereis(NewRelic.Transaction.ErlangTraceSupervisor)
    Process.monitor(supervisor)
    Process.exit(supervisor, :kill)
    assert_receive {:DOWN, _ref, _, ^supervisor, _}

    Process.sleep(100)
  end
end
