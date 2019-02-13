defmodule MetricTransactionTest do
  use ExUnit.Case
  use Plug.Test

  alias NewRelic.Harvest.Collector

  defmodule TestPlugAppForward do
    import Plug.Conn

    def init(opts), do: opts
    def call(conn, _opts), do: send_resp(conn, 200, "ok")
  end

  defmodule Status do
    use Plug.Router

    plug(:match)
    plug(:dispatch)

    get("/check", do: send_resp(conn, 200, "ok"))
    get("/info", do: send_resp(conn, 200, "ok"))
  end

  defmodule External do
    use NewRelic.Tracer
    @trace {:call, category: :external}
    def call, do: :make_request
  end

  defmodule TestPlugApp do
    use Plug.Router
    use NewRelic.Transaction

    plug(:match)
    plug(:dispatch)

    get "/foo/:blah" do
      External.call()
      send_resp(conn, 200, blah)
    end

    get "/fail" do
      raise "FAIL"
      send_resp(conn, 200, "won't get here")
    end

    get "/ordering/:one/test/:two/ok/:three" do
      send_resp(conn, 200, "ok")
    end

    get "/custom_name" do
      NewRelic.set_transaction_name("/very/unique/name")
      send_resp(conn, 200, "ok")
    end

    get "/named_wildcard/*public_variable_name" do
      send_resp(conn, 200, "ok")
    end

    get "/unnamed_wildcard/*_secret_variable_name" do
      send_resp(conn, 200, "ok")
    end

    get "/fancy/:transaction/:_names/*supported" do
      send_resp(conn, 200, "hello")
    end

    forward("/forward/a", to: TestPlugAppForward)
    forward("/forward/b", to: TestPlugAppForward)
    forward("/status", to: Status)
  end

  setup do
    TestHelper.restart_harvest_cycle(NewRelic.Harvest.Collector.Metric.HarvestCycle)

    on_exit(fn ->
      TestHelper.pause_harvest_cycle(NewRelic.Harvest.Collector.Metric.HarvestCycle)
    end)
  end

  test "Basic transaction" do
    TestPlugApp.call(conn(:get, "/foo/1"), [])

    metrics = TestHelper.gather_harvest(Collector.Metric.Harvester)

    assert TestHelper.find_metric(metrics, "WebTransaction/Plug/GET//foo/:blah")

    apdex = TestHelper.find_metric(metrics, "Apdex")

    assert [_, [1, _, _, _, _, _]] = apdex

    assert TestHelper.find_metric(metrics, "External/MetricTransactionTest.External.call/all")
    assert TestHelper.find_metric(metrics, "External/allWeb")
  end

  test "Failed transaction" do
    TestHelper.request(TestPlugApp, conn(:get, "/fail"))

    metrics = TestHelper.gather_harvest(Collector.Metric.Harvester)

    assert TestHelper.find_metric(metrics, "Errors/all")
    apdex = TestHelper.find_metric(metrics, "Apdex", 0)

    assert [_, [_, _, 1, _, _, _]] = apdex
  end

  test "Custom transaction names" do
    TestPlugApp.call(conn(:get, "/custom_name"), [])

    metrics = TestHelper.gather_harvest(Collector.Metric.Harvester)

    assert TestHelper.find_metric(metrics, "WebTransaction/very/unique/name")
  end

  test "fancy transaction names" do
    TestPlugApp.call(conn(:get, "/fancy/transaction/names/supported/here!"), [])

    metrics = TestHelper.gather_harvest(Collector.Metric.Harvester)

    assert TestHelper.find_metric(
             metrics,
             "WebTransaction/Plug/GET//fancy/:transaction/:_names/*supported"
           )
  end

  test "Forwarding transaction names" do
    TestHelper.request(TestPlugApp, conn(:get, "/status/check"))
    TestHelper.request(TestPlugApp, conn(:get, "/status/check"))
    TestHelper.request(TestPlugApp, conn(:get, "/status/info"))

    metrics = TestHelper.gather_harvest(Collector.Metric.Harvester)

    assert TestHelper.find_metric(metrics, "WebTransaction/Plug/GET//status/check", 2)
    assert TestHelper.find_metric(metrics, "WebTransaction/Plug/GET//status/info")
  end
end
