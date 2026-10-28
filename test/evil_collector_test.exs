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

  describe "connect retry" do
    @connect_response %{
      "return_value" => %{
        "redirect_host" => "localhost",
        "agent_run_id" => "retry-run-id",
        "entity_guid" => "retry-entity-guid",
        "trusted_account_key" => "190",
        "account_id" => 190,
        "primary_application_id" => "1",
        "apdex_t" => 0.5,
        "request_headers_map" => %{},
        "sampling_target" => 10,
        "sampling_target_period_in_seconds" => 60,
        "data_methods" => %{},
        "data_report_period" => 60,
        "event_harvest_config" => %{
          "report_period_ms" => 60_000,
          "harvest_limits" => %{
            "analytic_event_data" => 100,
            "custom_event_data" => 100,
            "error_event_data" => 100,
            "span_event_data" => 100
          }
        }
      }
    }

    @tag :capture_log
    test "Schedule a retry when unable to preconnect" do
      TestHelper.run_with(:application_config, connect_backoff_seconds: [0])

      # Don't start an EvilCollector
      {:noreply, state} = Collector.AgentRun.handle_continue(:preconnect, %{})

      assert state.status == :error_during_preconnect
      assert state.connect_attempts == 1
      assert_receive :retry_connect

      assert {:noreply, state, {:continue, :preconnect}} =
               Collector.AgentRun.handle_info(:retry_connect, state)

      refute Map.has_key?(state, :retry_timer)
    end

    @tag :capture_log
    test "Back off between retries following the agent spec sequence" do
      state =
        Enum.reduce([15, 15, 30, 60, 120, 300, 300], %{}, fn expected_seconds, state ->
          {:noreply, state} = Collector.AgentRun.handle_continue(:preconnect, state)

          remaining_ms = Process.read_timer(state.retry_timer)
          assert remaining_ms <= :timer.seconds(expected_seconds)
          assert remaining_ms > :timer.seconds(expected_seconds) - 1_000

          state
        end)

      assert state.connect_attempts == 7
      Process.cancel_timer(state.retry_timer)
    end

    @tag :capture_log
    test "Keep a single pending retry" do
      {:noreply, state} = Collector.AgentRun.handle_continue(:preconnect, %{})
      first_timer = state.retry_timer

      {:noreply, state} = Collector.AgentRun.handle_info(:reconnect, state)

      assert Process.read_timer(first_timer) == false
      assert is_integer(Process.read_timer(state.retry_timer))
      Process.cancel_timer(state.retry_timer)
    end

    @tag :capture_log
    test "Retry when a reconnect fails" do
      TestHelper.run_with(:application_config, connect_backoff_seconds: [0])

      {:noreply, state} = Collector.AgentRun.handle_info(:reconnect, %{status: :connected})

      assert state.status != :connected
      assert_receive :retry_connect
    end

    @tag :capture_log
    test "Don't retry when the agent is disabled" do
      TestHelper.run_with(:application_config, connect_backoff_seconds: [0])
      TestHelper.run_with(:nr_config, harvest_enabled: false)

      {:noreply, state} = Collector.AgentRun.handle_continue(:preconnect, %{})

      assert state.status == :error_during_preconnect
      refute Map.has_key?(state, :retry_timer)
      refute_receive :retry_connect, 50
    end

    @tag :capture_log
    test "Don't retry when the collector is bypassed" do
      TestHelper.run_with(:application_config, connect_backoff_seconds: [0])
      TestHelper.run_with(:application_config, bypass_collector: true)

      {:noreply, state} = Collector.AgentRun.handle_continue(:preconnect, %{})

      assert state.status == :error_during_preconnect
      refute Map.has_key?(state, :retry_timer)
      refute_receive :retry_connect, 50
    end

    @tag :capture_log
    test "Complete the boot once a retry connects" do
      TestHelper.run_with(:application_config, connect_backoff_seconds: [0])
      TestHelper.run_with(:nr_agent_run, [])
      TestHelper.run_with(:nr_entity_metadata, [])
      saved_agent_run = :ets.tab2list(Collector.AgentRun)

      on_exit(fn ->
        :ets.delete_all_objects(Collector.AgentRun)
        :ets.insert(Collector.AgentRun, saved_agent_run)
      end)

      # First attempt fails: no collector is running yet
      {:noreply, state} = Collector.AgentRun.handle_continue(:preconnect, %{})
      assert_receive :retry_connect

      EvilCollector.start(code: 200, body: NewRelic.JSON.encode!(@connect_response))

      {:noreply, state, {:continue, :preconnect}} =
        Collector.AgentRun.handle_info(:retry_connect, state)

      {:noreply, state, {:continue, :connect}} =
        Collector.AgentRun.handle_continue(:preconnect, state)

      {:noreply, state, {:continue, :complete_boot}} =
        Collector.AgentRun.handle_continue(:connect, state)

      assert state.status == :connected
      assert state.connect_attempts == 0
      refute Map.has_key?(state, :retry_timer)
      refute_receive :retry_connect, 50

      EvilCollector.stop()
    end
  end
end
