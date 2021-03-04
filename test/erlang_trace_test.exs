defmodule ErlangTraceTest do
  use ExUnit.Case, async: false

  test "disable and re-enable Agent's usage of `:erlang.trace`" do
    first_pid = Process.whereis(NewRelic.Transaction.ErlangTrace)
    assert is_pid(first_pid)
    Process.monitor(first_pid)

    NewRelic.disable_erlang_trace()

    assert_receive {:DOWN, _ref, _, ^first_pid, _}

    NewRelic.enable_erlang_trace()

    second_pid = Process.whereis(NewRelic.Transaction.ErlangTrace)
    assert is_pid(second_pid)
    assert first_pid != second_pid
  end

  test "config option to disable at boot" do
    # Pretend the app is starting up with the config option
    Application.put_env(:new_relic_agent, :disable_erlang_trace, true)

    supervisor = Process.whereis(NewRelic.Transaction.ErlangTraceSupervisor)
    Process.monitor(supervisor)
    Process.exit(supervisor, :kill)
    assert_receive {:DOWN, _ref, _, ^supervisor, _}

    Process.sleep(100)

    # Make sure we didn't start the ErlangTrace process
    assert Process.whereis(NewRelic.Transaction.ErlangTraceSupervisor)
    refute Process.whereis(NewRelic.Transaction.ErlangTrace)

    # Pretend the app is starting up with the default setting
    Application.delete_env(:new_relic_agent, :disable_erlang_trace)

    supervisor = Process.whereis(NewRelic.Transaction.ErlangTraceSupervisor)
    Process.monitor(supervisor)
    Process.exit(supervisor, :kill)
    assert_receive {:DOWN, _ref, _, ^supervisor, _}

    Process.sleep(100)

    # Make sure it starts up enabled
    assert Process.whereis(NewRelic.Transaction.ErlangTraceSupervisor)
    assert Process.whereis(NewRelic.Transaction.ErlangTrace)
  end
end
