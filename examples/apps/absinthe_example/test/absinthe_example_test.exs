defmodule AbsintheExampleTest do
  use ExUnit.Case

  alias NewRelic.Harvest.TelemetrySdk
  alias NewRelic.Harvest.Collector

  setup_all context, do: TestSupport.simulate_agent_enabled(context)
  setup_all context, do: TestSupport.simulate_agent_run(context, trace_mode: :infinite)

  test "Absinthe instrumentation" do
    TestSupport.restart_harvest_cycle(Collector.Metric.HarvestCycle)
    TestSupport.restart_harvest_cycle(TelemetrySdk.Spans.HarvestCycle)

    {:ok, %{body: _body}} =
      request("""
      query TestQuery {
       one {
         two {
           three
         }
       }
      }
      """)

    metrics = TestSupport.gather_harvest(Collector.Metric.Harvester)

    assert TestSupport.find_metric(metrics, "WebTransaction")

    assert TestSupport.find_metric(
             metrics,
             "WebTransactionTotalTime/Absinthe/AbsintheExample.Schema/query/one.two.three"
           )

    [%{spans: spans}] = TestSupport.gather_harvest(TelemetrySdk.Spans.Harvester)

    do_three_fn_trace =
      Enum.find(spans, fn %{attributes: attr} ->
        attr[:name] == "AbsintheExample.Resolvers.do_three/0"
      end)

    operation =
      Enum.find(spans, fn %{attributes: attr} ->
        attr[:name] == "query:TestQuery"
      end)

    one_resolver =
      Enum.find(spans, fn %{attributes: attr} ->
        attr[:name] == "&AbsintheExample.Resolvers.one/3"
      end)

    # TODO: Make 3 a fn
    three_resolver =
      Enum.find(spans, fn %{attributes: attr} ->
        attr[:name] == "&AbsintheExample.Resolvers.three/3"
      end)

    assert one_resolver.attributes[:"absinthe.field.path"] == "one"
    assert three_resolver.attributes[:"absinthe.field.path"] == "one.two.three"

    assert operation.attributes[:"absinthe.operation.name"] == "TestQuery"
    assert operation.attributes[:"absinthe.operation.type"] == "query"

    assert three_resolver.attributes[:"duration.ms"] < 10

    assert three_resolver.attributes[:"duration.ms"] >
             do_three_fn_trace.attributes[:"duration.ms"]

    assert operation.attributes[:"duration.ms"] >
             three_resolver.attributes[:"duration.ms"]
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
