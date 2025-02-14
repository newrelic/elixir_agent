defmodule PhxExampleTest do
  use ExUnit.Case

  alias NewRelic.Harvest.Collector

  setup_all do
    TestHelper.simulate_agent_enabled()
  end

  setup do
    TestHelper.restart_harvest_cycle(Collector.Metric.HarvestCycle)
    TestHelper.restart_harvest_cycle(Collector.TransactionEvent.HarvestCycle)
    TestHelper.restart_harvest_cycle(Collector.SpanEvent.HarvestCycle)
    TestHelper.restart_harvest_cycle(Collector.ErrorTrace.HarvestCycle)
    NewRelic.DistributedTrace.BackoffSampler.reset()
    :ok
  end

  for server <- [:cowboy, :bandit] do
    describe "Testing #{server}:" do
      test "Phoenix metrics generated" do
        {:ok, %{body: body}} = request("/phx/bar", unquote(server))
        assert body =~ "Welcome to Phoenix"

        metrics = TestHelper.gather_harvest(Collector.Metric.Harvester)

        assert TestHelper.find_metric(
                 metrics,
                 "WebTransaction/Phoenix/PhxExampleWeb.PageController/index"
               )

        [[_, event]] = TestHelper.gather_harvest(Collector.TransactionEvent.Harvester)

        if event[:"bandit.resp_duration_ms"] do
          assert event[:"bandit.resp_duration_ms"] > 0
        end

        assert event[:"phoenix.endpoint"] =~ "PhxExampleWeb"
        assert event[:"phoenix.router"] == "PhxExampleWeb.Router"
        assert event[:"phoenix.controller"] == "PhxExampleWeb.PageController"
        assert event[:"phoenix.action"] == "index"
        assert event[:status] == 200

        [
          %{name: "WebTransactionTotalTime", scope: ""},
          [1, value, _, _, _, _]
        ] =
          TestHelper.find_metric(
            metrics,
            "WebTransactionTotalTime"
          )

        assert_in_delta value, 0.3, 0.1
      end

      test "Phoenix metrics generated for LiveView" do
        {:ok, %{body: body}} = request("/phx/home", unquote(server))
        assert body =~ "Some content"

        metrics = TestHelper.gather_harvest(Collector.Metric.Harvester)

        assert TestHelper.find_metric(
                 metrics,
                 "WebTransaction/Phoenix/PhxExampleWeb.HomeLive/index"
               )

        [[_, event]] = TestHelper.gather_harvest(Collector.TransactionEvent.Harvester)

        assert event[:"phoenix.endpoint"] =~ "PhxExampleWeb"
        assert event[:"phoenix.router"] == "PhxExampleWeb.Router"
        assert event[:"phoenix.controller"] == "Phoenix.LiveView.Plug"
        assert event[:"phoenix.action"] == "index"
        assert event[:status] == 200
      end

      test "Phoenix spans generated" do
        {:ok, %{body: body}} = request("/phx/home", unquote(server))
        assert body =~ "Some content"

        span_events = TestHelper.gather_harvest(Collector.SpanEvent.Harvester)

        tx_span = TestHelper.find_event(span_events, "/Phoenix/PhxExampleWeb.HomeLive/index")
        process_span = TestHelper.find_event(span_events, "Transaction Root Process")
        mount_span = TestHelper.find_event(span_events, "PhxExampleWeb.HomeLive:index.mount")

        assert process_span[:parentId] == tx_span[:guid]
        assert mount_span[:"live_view.params"]
      end

      @endpoint PhxExampleWeb.Endpoint
      test "Live View transaction and spans generated" do
        import Phoenix.ConnTest
        import Phoenix.LiveViewTest

        conn =
          Phoenix.ConnTest.build_conn()
          |> Plug.Test.init_test_session([])

        conn = get(conn, "/phx/home")
        assert html_response(conn, 200) =~ "<p>Some content</p>"

        {:ok, _view, _html} = live(conn)

        span_events = TestHelper.gather_harvest(Collector.SpanEvent.Harvester)

        tx_span =
          TestHelper.find_span(span_events, "/Phoenix.LiveView/Live/PhxExampleWeb.HomeLive/index")

        process_span = TestHelper.find_span(span_events, "Transaction Root Process")
        mount_span = TestHelper.find_span(span_events, "PhxExampleWeb.HomeLive:index.mount")
        render_span = TestHelper.find_span(span_events, "PhxExampleWeb.HomeLive:index.render")

        assert tx_span[:"live_view.endpoint"] == "PhxExampleWeb.Endpoint"

        assert process_span[:parentId] == tx_span[:guid]
        assert mount_span[:parentId] == process_span[:guid]
        assert render_span[:parentId] == process_span[:guid]
      end

      @tag :capture_log
      test "Phoenix error" do
        {:ok, %{body: body, status_code: 500}} = request("/phx/error", unquote(server))

        assert body =~ "Oops, Internal Server Error"

        metrics = TestHelper.gather_harvest(Collector.Metric.Harvester)

        assert TestHelper.find_metric(
                 metrics,
                 "WebTransaction/Phoenix/PhxExampleWeb.PageController/error"
               )

        [[_, event]] = TestHelper.gather_harvest(Collector.TransactionEvent.Harvester)

        assert event[:status] == 500
        assert event[:"phoenix.endpoint"] =~ "PhxExampleWeb"
        assert event[:"phoenix.router"] == "PhxExampleWeb.Router"
        assert event[:"phoenix.controller"] == "PhxExampleWeb.PageController"
        assert event[:"phoenix.action"] == "error"
        assert event[:error]
      end

      @tag :capture_log
      test "Phoenix LiveView error" do
        {:ok, %{body: body, status_code: 500}} = request("/phx/live_error", unquote(server))

        assert body =~ "Oops, Internal Server Error"

        metrics = TestHelper.gather_harvest(Collector.Metric.Harvester)

        assert TestHelper.find_metric(
                 metrics,
                 "WebTransaction/Phoenix/PhxExampleWeb.ErrorLive/index"
               )

        [[_, event]] = TestHelper.gather_harvest(Collector.TransactionEvent.Harvester)

        assert event[:status] == 500
        assert event[:"phoenix.endpoint"] =~ "PhxExampleWeb"
        assert event[:"phoenix.router"] == "PhxExampleWeb.Router"
        assert event[:"phoenix.controller"] == "Phoenix.LiveView.Plug"
        assert event[:"phoenix.action"] == "index"
        assert event[:error]
      end

      test "Phoenix route not found" do
        {:ok, %{body: body, status_code: 404}} = request("/not_found", unquote(server))
        assert body =~ "Not Found"

        metrics = TestHelper.gather_harvest(Collector.Metric.Harvester)

        metric =
          case unquote(server) do
            :cowboy -> "WebTransaction/Phoenix/PhxExampleWeb.Endpoint/GET"
            :bandit -> "WebTransaction/Phoenix/PhxExampleWeb.BanditEndpoint/GET"
          end

        assert TestHelper.find_metric(metrics, metric)

        [[_, event]] = TestHelper.gather_harvest(Collector.TransactionEvent.Harvester)

        assert event[:status] == 404
        assert event[:"phoenix.endpoint"] =~ "PhxExampleWeb"
        assert event[:"phoenix.router"] == "PhxExampleWeb.Router"
        refute event[:"phoenix.controller"]
        refute event[:error]

        errors = TestHelper.gather_harvest(Collector.ErrorTrace.Harvester)
        assert errors == []
      end
    end
  end

  defp request(path, server) do
    config =
      case server do
        :cowboy -> Application.get_env(:phx_example, PhxExampleWeb.Endpoint)
        :bandit -> Application.get_env(:phx_example, PhxExampleWeb.BanditEndpoint)
      end

    NewRelic.Util.HTTP.get("http://localhost:#{config[:http][:port]}#{path}")
  end
end
