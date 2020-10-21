defmodule ErlangTraceTest do
  use ExUnit.Case

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
end
