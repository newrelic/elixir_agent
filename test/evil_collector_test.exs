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

    def start(duration: duration) do
      {:ok, _} =
        Plug.Cowboy.http(
          EvilCollector,
          [test_pid: self(), duration: duration],
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

    def call(conn, test_pid: test_pid, duration: duration) do
      Process.sleep(duration)
      send(test_pid, :collector_took_a_while)
      send_resp(conn, 200, ~s({"return_value": "took a while"}))
    end
  end

  setup_all do
    config = [
      collector_instance_host: "localhost",
      port: 8881,
      scheme: "http",
      license_key: "key",
      app_name: "tester",
      harvest_enabled: true
    ]

    original =
      Enum.map(config, fn {key, _} -> {key, Application.get_env(:new_relic_agent, key)} end)

    Enum.each(config, fn {key, value} -> Application.put_env(:new_relic_agent, key, value) end)

    on_exit(fn ->
      Enum.each(original, fn
        {key, nil} -> Application.delete_env(:new_relic_agent, key)
        {key, value} -> Application.put_env(:new_relic_agent, key, value)
      end)
    end)

    :ok
  end

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

  test "Handle unexpected HTTP code" do
    EvilCollector.start(code: 404, body: "??")

    {:noreply, %{status: :error_during_preconnect}} =
      Collector.AgentRun.handle_continue(:preconnect, %{})

    assert_received(:attempt)

    EvilCollector.stop()
  end

  test "Handle when unable to connect" do
    # Don't start an EvilCollector
    assert {:error, reason} = Collector.Protocol.preconnect()
    assert {:failed_connect, _} = reason
  end

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

  test "long collector response don't prevent app starting" do
    # simulate collector with a slow response
    EvilCollector.start(duration: 800)
    Collector.AgentRun.reconnect()

    # ensure the EnabledSupervisorManager starts right away
    {:ok, _} = NewRelic.EnabledSupervisorManager.start_link(:test)

    # verify a process under the EnabledSupervisor eventually starts
    assert_receive(:collector_took_a_while, 1000)
    Process.sleep(100)
    assert Process.whereis(NewRelic.Sampler.Beam)

    EvilCollector.stop()
  end
end
