defmodule EctoExampleTest do
  use ExUnit.Case

  alias NewRelic.Harvest.Collector

  setup_all do
    # Simulate the agent fully starting up
    Process.whereis(Collector.TaskSupervisor) ||
      NewRelic.EnabledSupervisor.start_link(enabled: true)

    :ok
  end

  test "basic HTTP request flow" do
    restart_harvest_cycle(Collector.Metric.HarvestCycle)

    {:ok, %{body: body}} = request()
    assert body =~ "world"

    metrics = gather_harvest(Collector.Metric.Harvester)

    assert find_metric(
             metrics,
             "Datastore/statement/Postgres/counts/insert",
             1
           )

    assert find_metric(
             metrics,
             "Datastore/statement/MySQL/counts/insert",
             1
           )
  end

  def request() do
    http_port = Application.get_env(:ecto_example, :http_port)

    {:ok, {{_, _status_code, _}, _headers, body}} =
      :httpc.request('http://localhost:#{http_port}/hello')

    {:ok, %{body: to_string(body)}}
  end

  defp gather_harvest(harvester) do
    Process.sleep(300)
    harvester.gather_harvest
  end

  defp restart_harvest_cycle(harvest_cycle) do
    GenServer.call(harvest_cycle, :restart)
  end

  defp find_metric(metrics, name, call_count) do
    Enum.find(metrics, fn
      [%{name: ^name}, [^call_count, _, _, _, _, _]] -> true
      _ -> false
    end)
  end
end
