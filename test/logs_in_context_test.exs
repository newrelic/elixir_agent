defmodule LogsInContextTest do
  use ExUnit.Case
  import ExUnit.CaptureLog
  require Logger

  alias NewRelic.Harvest.TelemetrySdk

  test "LogsInContext formats log messages" do
    TestHelper.run_with(:logs_in_context, :forwarder)

    log_line =
      capture_log([colors: [enabled: false]], fn ->
        Task.async(fn ->
          NewRelic.start_transaction("TransactionCategory", "LogsInContext")

          Logger.metadata(foo: :bar, now: DateTime.utc_now())
          Logger.error("FOO", baz: :qux)
        end)
        |> Task.await()
      end)

    # Console logging is transformed into JSON structured log lines
    [_, json] = Regex.run(~r/.*({.*}).*/, log_line)
    log = NewRelic.JSON.decode!(json)

    assert log["timestamp"] |> is_integer
    assert log["message"] == "FOO"
    assert log["log.level"] == "error"
    assert log["module.name"] == inspect(__MODULE__)
    assert log["trace.id"] |> is_binary
    assert log["metadata.foo"] == "bar"
    assert log["metadata.now"] |> is_binary
    assert log["metadata.baz"] == "qux"
  end

  test "LogsInContext formats report keyword messages" do
    TestHelper.run_with(:logs_in_context, :forwarder)

    log_line =
      capture_log([colors: [enabled: false]], fn ->
        Task.async(fn ->
          NewRelic.start_transaction("TransactionCategory", "LogsInContext")

          Logger.error(foo: "BAR", baz: :qux)
        end)
        |> Task.await()
      end)

    [_, json] = Regex.run(~r/.*({.*}).*/, log_line)
    log = NewRelic.JSON.decode!(json)

    assert log["timestamp"] |> is_integer
    assert log["log.level"] == "error"
    assert log["module.name"] == inspect(__MODULE__)
    assert log["trace.id"] |> is_binary
    assert log["foo"] == "BAR"
    assert log["baz"] == "qux"
  end

  test "LogsInContext formats log messages from Io Lists" do
    TestHelper.run_with(:logs_in_context, :forwarder)

    log_line =
      capture_log([colors: [enabled: false]], fn ->
        Task.async(fn ->
          NewRelic.start_transaction("TransactionCategory", "LogsInContext")
          Logger.error(["FOO", 32, "BAR"])
        end)
        |> Task.await()
      end)

    [_, json] = Regex.run(~r/.*({.*}).*/, log_line)
    log = NewRelic.JSON.decode!(json)

    assert log["message"] == "FOO BAR"
  end

  test "LogsInContext in :direct mode" do
    TestHelper.restart_harvest_cycle(TelemetrySdk.Logs.HarvestCycle)
    TestHelper.restart_harvest_cycle(NewRelic.Harvest.Collector.TransactionErrorEvent.HarvestCycle)
    TestHelper.run_with(:logs_in_context, :direct)

    log_output =
      capture_log(fn ->
        Task.async(fn ->
          NewRelic.start_transaction("TransactionCategory", "LogsInContext")

          Logger.metadata(foo: :bar, now: DateTime.utc_now())
          Logger.error("FOO")
        end)
        |> Task.await()
      end)

    # Console logging continues to function
    assert log_output =~ "[error]"
    assert log_output =~ "FOO"

    [harvest] = TestHelper.gather_harvest(TelemetrySdk.Logs.Harvester)

    assert harvest[:logs] |> length > 0
    assert harvest[:common][:attributes] |> Map.has_key?(:"entity.guid")
  end

  test "prevent overload of log harvester" do
    TestHelper.run_with(:logs_in_context, :direct)
    TestHelper.run_with(:application_config, log_reservoir_size: 3)
    TestHelper.restart_harvest_cycle(TelemetrySdk.Logs.HarvestCycle)

    capture_log(fn ->
      Logger.error("1")
      Logger.error("2")
      Logger.error("3")
      Logger.error("4")
      Logger.error("5")
    end)

    [harvest] = TestHelper.gather_harvest(TelemetrySdk.Logs.Harvester)

    assert length(harvest[:logs]) == 3
  end
end
