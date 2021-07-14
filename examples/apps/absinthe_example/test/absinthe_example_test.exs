defmodule AbsintheExampleTest do
  use ExUnit.Case

  alias NewRelic.Harvest.TelemetrySdk
  alias NewRelic.Harvest.Collector

  setup_all context, do: TestSupport.simulate_agent_enabled(context)
  setup_all context, do: TestSupport.simulate_agent_run(context)

  test "Absinthe instrumentation" do
    TestSupport.restart_harvest_cycle(Collector.Metric.HarvestCycle)
    TestSupport.restart_harvest_cycle(TelemetrySdk.Spans.HarvestCycle)

    {:ok, %{body: body}} =
      request("""
      query TestQuery {
       echo(this: "hello, world")
       one {
         two {
           three
         }
       }
      }
      """)

    assert body =~ "hello, world"

    metrics = TestSupport.gather_harvest(Collector.Metric.Harvester)

    assert TestSupport.find_metric(metrics, "WebTransaction")

    assert TestSupport.find_metric(
             metrics,
             "WebTransactionTotalTime/Absinthe/AbsintheExample.Schema/query/TestQuery"
           )

    [%{spans: spans}] = TestSupport.gather_harvest(TelemetrySdk.Spans.Harvester)

    do_three_fn_trace =
      Enum.find(spans, fn %{attributes: attr} ->
        attr[:name] == "AbsintheExample.Resolvers.do_three/0"
      end)

    three_resolver =
      Enum.find(spans, fn %{id: id} ->
        id == do_three_fn_trace.attributes[:"parent.id"]
      end)

    operation =
      Enum.find(spans, fn %{id: id} ->
        id == three_resolver.attributes[:"parent.id"]
      end)

    one_resolver =
      Enum.find(spans, fn %{attributes: attr} ->
        attr[:"absinthe.field.path"] == "one"
      end)

    # Resolver execution isn't nested like the graphql query
    assert one_resolver.attributes[:"parent.id"] == operation.id

    assert operation.attributes[:"absinthe.operation.name"] == "TestQuery"
    assert operation.attributes[:"absinthe.operation.type"] == "query"

    assert three_resolver.attributes[:"duration.ms"] < 10

    assert three_resolver.attributes[:"duration.ms"] >
             do_three_fn_trace.attributes[:"duration.ms"]

    assert operation.attributes[:"duration.ms"] >
             three_resolver.attributes[:"duration.ms"]
  end

  test "Query naming" do
    TestSupport.restart_harvest_cycle(Collector.Metric.HarvestCycle)

    {:ok, %{body: body}} =
      request("""
      query {
       one {
         two {
           three
         }
       }
      }
      """)

    metrics = TestSupport.gather_harvest(Collector.Metric.Harvester)

    assert TestSupport.find_metric(
             metrics,
             "WebTransactionTotalTime/Absinthe/AbsintheExample.Schema/query/one.two.three"
           )
  end

  defp request(query) do
    http_port = Application.get_env(:absinthe_example, :http_port)
    body = Jason.encode!(%{query: query})
    request = {'http://localhost:#{http_port}/graphql', [], 'application/json', body}

    with {:ok, {{_, status_code, _}, _headers, body}} <-
           :httpc.request(:post, request, [], []) do
      {:ok, %{status_code: status_code, body: to_string(body)}}
    end
  end
end
