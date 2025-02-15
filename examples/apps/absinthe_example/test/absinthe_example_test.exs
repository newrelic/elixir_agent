defmodule AbsintheExampleTest do
  use ExUnit.Case

  alias NewRelic.Harvest.TelemetrySdk
  alias NewRelic.Harvest.Collector

  setup_all do
    TestHelper.simulate_agent_enabled()
    TestHelper.simulate_agent_run(trace_mode: :infinite)
  end

  test "Absinthe instrumentation" do
    TestHelper.restart_harvest_cycle(Collector.Metric.HarvestCycle)
    TestHelper.restart_harvest_cycle(TelemetrySdk.Spans.HarvestCycle)

    {:ok, %{body: _body}} = request("query TestQuery { one { two { three(value: 3) } } }")

    metrics = TestHelper.gather_harvest(Collector.Metric.Harvester)

    assert TestHelper.find_metric(metrics, "WebTransaction")

    assert TestHelper.find_metric(
             metrics,
             "WebTransactionTotalTime/Absinthe/AbsintheExample.Schema/query/one.two.three"
           )

    [%{spans: spans}] = TestHelper.gather_harvest(TelemetrySdk.Spans.Harvester)

    spansaction =
      Enum.find(spans, fn %{attributes: attr} ->
        attr[:name] == "Absinthe/AbsintheExample.Schema/query/one.two.three"
      end)

    tx_root_process =
      Enum.find(spans, fn %{attributes: attr} ->
        attr[:name] == "Transaction Root Process"
      end)

    process =
      Enum.find(spans, fn %{attributes: attr} ->
        attr[:name] == "Process"
      end)

    operation =
      Enum.find(spans, fn %{attributes: attr} ->
        attr[:name] == "Absinthe/Operation/query:TestQuery"
      end)

    one_resolver =
      Enum.find(spans, fn %{attributes: attr} ->
        attr[:name] == "&AbsintheExample.Resolvers.one/3"
      end)

    three_resolver =
      Enum.find(spans, fn %{attributes: attr} ->
        attr[:name] == "&AbsintheExample.Resolvers.three/3"
      end)

    do_three_fn_trace =
      Enum.find(spans, fn %{attributes: attr} ->
        attr[:name] == "AbsintheExample.Resolvers.do_three/1"
      end)

    assert operation.attributes[:"absinthe.operation.name"] == "TestQuery"
    assert operation.attributes[:"absinthe.operation.type"] == "query"
    assert operation.attributes[:"absinthe.schema"] == "AbsintheExample.Schema"
    assert operation.attributes[:"absinthe.query"] |> is_binary

    assert spansaction.attributes[:"absinthe.operation.name"] == "TestQuery"
    assert spansaction.attributes[:"absinthe.operation.type"] == "query"
    assert spansaction.attributes[:"absinthe.schema"] == "AbsintheExample.Schema"
    assert spansaction.attributes[:"absinthe.query"] |> is_binary

    assert one_resolver.attributes[:"absinthe.field.path"] == "one"
    assert one_resolver.attributes[:"absinthe.field.name"] == "one"
    assert one_resolver.attributes[:"absinthe.field.type"] == "OneThing"
    assert one_resolver.attributes[:"absinthe.field.parent_type"] == "RootQueryType"
    refute one_resolver.attributes[:"absinthe.field.arguments"]

    assert three_resolver.attributes[:"absinthe.field.path"] == "one.two.three"
    assert three_resolver.attributes[:"absinthe.field.name"] == "three"
    assert three_resolver.attributes[:"absinthe.field.type"] == "Int"
    assert three_resolver.attributes[:"absinthe.field.parent_type"] == "TwoThing"
    assert three_resolver.attributes[:"absinthe.field.arguments"] == "%{value: 3}"

    assert one_resolver.attributes[:"parent.id"] == operation.id
    assert three_resolver.attributes[:"parent.id"] == operation.id
    assert do_three_fn_trace.attributes[:"parent.id"] == three_resolver.id
    assert operation.attributes[:"parent.id"] == process.id
    assert process.attributes[:"parent.id"] == tx_root_process.id
    assert tx_root_process.attributes[:"parent.id"] == spansaction.id
    assert spansaction.attributes[:"nr.entryPoint"] == true

    Enum.each(spans, fn span ->
      assert span[:"trace.id"] == spansaction[:"trace.id"]
      assert span.attributes[:transactionId] == spansaction.attributes[:transactionId]
    end)
  end

  defp request(query) do
    http_port = Application.get_env(:absinthe_example, :http_port)
    body = Jason.encode!(%{query: query})
    request = {~c"http://localhost:#{http_port}/graphql", [], ~c"application/json", body}

    with {:ok, {{_, status_code, _}, _headers, body}} <-
           :httpc.request(:post, request, [], []) do
      {:ok, %{status_code: status_code, body: to_string(body)}}
    end
  end
end
