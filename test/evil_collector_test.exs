defmodule EvilCollectorTest do
  use ExUnit.Case
  alias NewRelic.Harvest.Collector

  defmodule EvilCollector do
    import Plug.Conn

    def start(code: code, body: body) do
      {:ok, _} =
        Plug.Cowboy.http(
          EvilCollector,
          [test_pid: self(), code: code, body: body],
          port: 8881
        )
    end

    def stop() do
      Plug.Cowboy.shutdown(EvilCollector.HTTP)
    end

    def init(options), do: options

    def call(conn, test_pid: test_pid, code: code, body: body) do
      send(test_pid, :attempt)
      send_resp(conn, code, body)
    end
  end

  setup_all do
    orginal_collector = Application.get_env(:new_relic_agent, :collector_instance_host)
    original_bypass = Application.get_env(:new_relic_agent, :bypass_collector)

    Application.put_env(:new_relic_agent, :collector_instance_host, "localhost")
    Application.put_env(:new_relic_agent, :bypass_collector, false)

    reset_config =
      TestHelper.update(:nr_config,
        port: 8881,
        scheme: "http",
        license_key: "key",
        harvest_enabled: true
      )

    on_exit(fn ->
      TestHelper.reset_env(:collector_instance_host, orginal_collector)
      TestHelper.reset_env(:bypass_collector, original_bypass)
      reset_config.()
    end)

    :ok
  end

  @tag :capture_log
  test "Retry on 503" do
    EvilCollector.start(code: 503, body: ":(")

    assert Collector.Protocol.metric_data([123, 0, 1, []]) == {:error, 503}
    assert_received(:attempt)
    assert_received(:attempt)

    EvilCollector.stop()
  end

  test "Short circuit reporting when not connected" do
    agent_run_id = nil
    assert {:error, :not_connected} = Collector.Protocol.transaction_trace([agent_run_id, []])
  end

  @tag :capture_log
  test "Handle unexpected HTTP code" do
    EvilCollector.start(code: 404, body: "??")

    {:noreply, %{status: :error_during_preconnect}} =
      Collector.AgentRun.handle_continue(:preconnect, %{})

    assert_received(:attempt)

    EvilCollector.stop()
  end

  @tag :capture_log
  test "Handle when unable to connect" do
    # Don't start an EvilCollector
    assert {:error, reason} = Collector.Protocol.preconnect()
    assert {:failed_connect, _} = reason
  end

  @tag :capture_log
  test "Log out collector error response" do
    EvilCollector.start(code: 418, body: "c(_)/")
    previous_logger = GenServer.call(NewRelic.Logger, {:logger, :memory})

    Collector.Protocol.preconnect()

    log = GenServer.call(NewRelic.Logger, :flush)
    assert log =~ "[ERROR]"
    assert log =~ "(418)"
    assert log =~ "c(_)/"

    GenServer.call(NewRelic.Logger, {:replace, previous_logger})
    EvilCollector.stop()
  end

  @tag :capture_log
  test "Handle mangled collector response" do
    EvilCollector.start(code: 200, body: "<badJSON>")
    previous_logger = GenServer.call(NewRelic.Logger, {:logger, :memory})

    Collector.Protocol.preconnect()

    log = GenServer.call(NewRelic.Logger, :flush)
    assert log =~ "[ERROR]"
    assert log =~ "Bad collector JSON"

    GenServer.call(NewRelic.Logger, {:replace, previous_logger})
    EvilCollector.stop()
  end

  @tag :capture_log
  test "Log out collector Exception" do
    exception = %{
      "exception" => %{
        "error_type" => "NewRelic::Agent::SomeKindOfException",
        "message" => "Longer message"
      }
    }

    EvilCollector.start(code: 415, body: Jason.encode!(exception))
    previous_logger = GenServer.call(NewRelic.Logger, {:logger, :memory})

    Collector.Protocol.preconnect()

    log = GenServer.call(NewRelic.Logger, :flush)
    assert log =~ "[ERROR]"
    assert log =~ "preconnect"
    assert log =~ "NewRelic::Agent::SomeKindOfException"
    assert log =~ "Longer message"

    GenServer.call(NewRelic.Logger, {:replace, previous_logger})
    EvilCollector.stop()
  end
end
