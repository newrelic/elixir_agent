defmodule ErlangTraceOverloadTest do
  use ExUnit.Case

  @test_queue_len 1
  @test_backoff 100

  @tag :capture_log
  test "Handle process spawn overload in ErlangTrace" do
    TestHelper.run_with(:application_config, overload_queue_len: @test_queue_len)
    TestHelper.run_with(:application_config, overload_backoff: @test_backoff)

    NewRelic.disable_erlang_trace()
    NewRelic.enable_erlang_trace()

    on_exit(fn ->
      NewRelic.disable_erlang_trace()
      NewRelic.enable_erlang_trace()
    end)

    first_pid = Process.whereis(NewRelic.Transaction.ErlangTrace)
    Process.monitor(first_pid)

    Task.async(fn ->
      NewRelic.start_transaction("Overload", "test")

      1..200
      |> Enum.to_list()
      |> Enum.map(fn _ ->
        Task.async(fn ->
          Process.sleep(1_000)
        end)
      end)
      |> Enum.map(fn task ->
        Task.await(task, :infinity)
      end)

      NewRelic.stop_transaction()
    end)
    |> Task.await(:infinity)

    # ErlangTrace will give up when it's overloaded all existing tracers will go away
    assert_receive {:DOWN, _ref, _, ^first_pid, {:shutdown, :overload}}, 1_000

    # ErlangTrace will be restarted after a backoff
    Process.sleep(@test_backoff * 2)

    second_pid = NewRelic.Transaction.ErlangTrace |> Process.whereis()
    assert is_pid(second_pid)

    assert first_pid != second_pid
  end
end
