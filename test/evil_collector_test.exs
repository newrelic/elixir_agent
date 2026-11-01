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
    TestHelper.run_with(:application_config, bypass_collector: false)
    TestHelper.run_with(:application_config, collector_instance_host: "localhost")

    TestHelper.run_with(:nr_config,
      port: 8881,
      scheme: "http",
      license_key: "key",
      harvest_enabled: true
    )

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

    state = %{status: :not_connected, connect_backoff: [0]}

    {:noreply, %{status: :error_during_preconnect}, {:continue, :retry_connect}} =
      Collector.AgentRun.handle_continue(:preconnect, state)

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

    EvilCollector.start(code: 415, body: NewRelic.JSON.encode!(exception))
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

  @tag :capture_log
  test "Retry when unable to connect" do
    EvilCollector.start(code: 404, body: "??")
    state = %{status: :preconnected, connect_backoff: [0]}

    {:noreply, state, {:continue, :retry_connect}} =
      Collector.AgentRun.handle_continue(:connect, state)

    assert state.status == :bad_connect_response

    EvilCollector.stop()
  end

  test "Reconnect when connected" do
    state = %{status: :connected, connect_backoff: [0]}

    {:noreply, ^state, {:continue, :preconnect}} =
      Collector.AgentRun.handle_info(:reconnect, state)
  end

  test "Ignore reconnect when not connected" do
    state = %{status: :error_during_preconnect, connect_backoff: [0]}

    {:noreply, ^state} = Collector.AgentRun.handle_info(:reconnect, state)
  end

  describe "AgentRun boot" do
    setup do
      on_exit(fn ->
        Application.put_env(:new_relic_agent, :bypass_collector, true)
        TestHelper.restart_agent_run()
        Application.put_env(:new_relic_agent, :bypass_collector, false)
      end)
    end

    @tag :capture_log
    test "Retry with backoff when unable to connect" do
      TestHelper.run_with(:application_config, connect_backoff_seconds: [0, 60])
      EvilCollector.start(code: 404, body: "??")

      TestHelper.restart_agent_run()

      assert_receive :attempt
      assert_receive :attempt
      refute_receive :attempt

      EvilCollector.stop()
    end

    @tag :capture_log
    test "Don't loop on 401" do
      TestHelper.run_with(:application_config, connect_backoff_seconds: [60])
      EvilCollector.start(code: 401, body: "{}")

      TestHelper.restart_agent_run()

      assert_receive :attempt
      refute_receive :attempt

      EvilCollector.stop()
    end

    @tag :capture_log
    test "Don't retry when the collector forces a disconnect" do
      TestHelper.run_with(:application_config, connect_backoff_seconds: [0])
      TestHelper.run_with(:application_config, harvest_enabled: true)
      TestHelper.run_with(:nr_config, [])
      EvilCollector.start(code: 410, body: "")
      previous_logger = GenServer.call(NewRelic.Logger, {:logger, :memory})

      TestHelper.restart_agent_run()

      assert_receive :attempt
      refute_receive :attempt

      log = GenServer.call(NewRelic.Logger, :flush)
      refute log =~ "retrying"

      GenServer.call(NewRelic.Logger, {:replace, previous_logger})
      EvilCollector.stop()
    end

    test "Don't connect when bypassing the collector" do
      TestHelper.run_with(:application_config, connect_backoff_seconds: [0])
      TestHelper.run_with(:application_config, bypass_collector: true)
      EvilCollector.start(code: 404, body: "??")
      previous_logger = GenServer.call(NewRelic.Logger, {:logger, :memory})

      TestHelper.restart_agent_run()

      refute_receive :attempt

      log = GenServer.call(NewRelic.Logger, :flush)
      refute log =~ "retrying"

      GenServer.call(NewRelic.Logger, {:replace, previous_logger})
      EvilCollector.stop()
    end
  end
end
