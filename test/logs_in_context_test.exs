defmodule LogsInContextTest do
  use ExUnit.Case
  import ExUnit.CaptureLog
  require Logger

  test "LogsInContext formats log messages" do
    Process.sleep(100)

    log_line =
      capture_log([colors: [enabled: false]], fn ->
        Task.async(fn ->
          NewRelic.start_transaction("TransactionCategory", "LogsInContext")

          Logger.metadata(foo: :bar, now: DateTime.utc_now())
          Logger.error("FOO")
        end)
        |> Task.await()
      end)

    log = Jason.decode!(log_line)

    assert log["timestamp"] |> is_integer
    assert log["message"] == "FOO"
    assert log["log.level"] == "error"
    assert log["module.name"] == inspect(__MODULE__)
    assert log["trace.id"] |> is_binary
    assert log["metadata.foo"] == "bar"
    assert log["metadata.now"] |> is_binary
  end
end
