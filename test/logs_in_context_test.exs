defmodule LogsInContextTest do
  use ExUnit.Case
  import ExUnit.CaptureLog
  require Logger

  alias NewRelic.Harvest.TelemetrySdk

  test "LogsInContext formats log messages" do
    configure_logs_in_context(:forward)

    log_line =
      capture_log([colors: [enabled: false]], fn ->
        Task.async(fn ->
          NewRelic.start_transaction("TransactionCategory", "LogsInContext")

          Logger.metadata(foo: :bar, now: DateTime.utc_now())
          Logger.error("FOO")
        end)
        |> Task.await()
      end)

    # Console logging is transformed into JSON structured log lines
    log = Jason.decode!(log_line)

    assert log["timestamp"] |> is_integer
    assert log["message"] == "FOO"
    assert log["log.level"] == "error"
    assert log["module.name"] == inspect(__MODULE__)
    assert log["trace.id"] |> is_binary
    assert log["metadata.foo"] == "bar"
    assert log["metadata.now"] |> is_binary
  end

  test "LogsInContext in :direct mode" do
    TestHelper.restart_harvest_cycle(TelemetrySdk.Logs.HarvestCycle)

    TestHelper.restart_harvest_cycle(
      NewRelic.Harvest.Collector.TransactionErrorEvent.HarvestCycle
    )

    configure_logs_in_context(:direct)

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

  @default_pattern "\n$time $metadata[$level] $levelpad$message\n"
  def configure_logs_in_context(mode) do
    Application.put_env(:new_relic_agent, :logs_in_context, mode)
    :logger.remove_primary_filter(:nr_logs_in_context)
    Logger.configure_backend(:console, format: @default_pattern)
    NewRelic.LogsInContext.Supervisor.setup_logs_in_context()
  end
end
