defmodule CollectorStubTest do
  use ExUnit.Case
  alias NewRelic.Harvest.Collector

  defmodule EvilCollectorPlug do
    import Plug.Conn

    def init(options), do: options

    def call(conn, test_pid: test_pid) do
      send(test_pid, :attempt)
      send_resp(conn, 503, ":(")
    end
  end

  test "Retry on 503" do
    {:ok, _} = Plug.Cowboy.http(EvilCollectorPlug, [test_pid: self()], port: 8881)

    with_config(
      [
        collector_instance_host: "localhost",
        port: 8881,
        scheme: "http",
        license_key: "license_key",
        harvest_enabled: true
      ],
      fn ->
        assert Collector.Protocol.metric_data([123, 0, 1, []]) == 503
        assert_received(:attempt)
        assert_received(:attempt)
      end
    )
  end

  defmodule TeapotCollectorPlug do
    import Plug.Conn

    def init(options), do: options

    def call(conn, []) do
      send_resp(conn, 418, "teapot")
    end
  end

  test "Log out collector error response" do
    previous_logger = GenServer.call(NewRelic.Logger, {:logger, :memory})
    {:ok, _} = Plug.Cowboy.http(TeapotCollectorPlug, [], port: 8882)

    with_config(
      [
        collector_instance_host: "localhost",
        license_key: "license_key",
        port: 8882,
        scheme: "http",
        harvest_enabled: true
      ],
      fn ->
        NewRelic.Harvest.Collector.Protocol.preconnect()

        log = GenServer.call(NewRelic.Logger, :flush)
        assert log =~ "[ERROR]"
        assert log =~ "(418)"
        assert log =~ "teapot"
      end
    )

    GenServer.call(NewRelic.Logger, {:replace, previous_logger})
  end

  def with_config(env, fun) do
    original_env =
      env |> Enum.map(fn {key, _} -> {key, Application.get_env(:new_relic_agent, key)} end)

    env |> Enum.each(fn {key, value} -> Application.put_env(:new_relic_agent, key, value) end)

    fun.()

    original_env
    |> Enum.each(fn
      {key, nil} -> Application.delete_env(:new_relic_agent, key)
      {key, value} -> Application.put_env(:new_relic_agent, key, value)
    end)
  end
end
