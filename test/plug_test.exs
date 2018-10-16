defmodule PlugTest do
  use ExUnit.Case
  use Plug.Test
  import ExUnit.CaptureLog

  defmodule NestedTestPlugApp do
    use Plug.Router
    use NewRelic.Transaction

    plug(:match)
    plug(:dispatch)

    get "/double" do
      send_resp(conn, 200, "Don't double instrument!")
    end
  end

  defmodule TestPlugApp do
    use Plug.Router
    use NewRelic.Transaction

    plug(:match)
    plug(:dispatch)

    match("/double", to: NestedTestPlugApp)

    get "/" do
      send_resp(conn, 200, "root")
    end
  end

  test "Don't fail if we double instrument, but do warn" do
    assert capture_log(fn ->
             TestHelper.request(TestPlugApp, conn(:get, "/double"))
           end) =~ "[warn]"
  end

  test "plug_name is set on the transaction" do
    conn = TestHelper.request(TestPlugApp, conn(:get, "/"))

    assert NewRelic.Util.AttrStore.collect(NewRelic.Transaction.Reporter, conn.request_pid)
           |> Map.get(:plug_name) == "/Plug/GET//"
  end

  test "Phoenix plug_name utilizes the controller and action names" do
    request_conn =
      conn(:get, "/")
      |> put_private(:phoenix_action, :show)
      |> put_private(:phoenix_controller, TestPlugApp)

    conn = TestHelper.request(TestPlugApp, request_conn)

    assert NewRelic.Util.AttrStore.collect(NewRelic.Transaction.Reporter, conn.request_pid)
           |> Map.get(:plug_name) == "/Phoenix/PlugTest.TestPlugApp/show"
  end
end
