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
end
