defmodule ProxyIntegrationTest do
  use ExUnit.Case

  @moduletag skip: "Tests require a running proxy on port 9000"

  # Eaily run a proxy:
  # docker run --rm -it -p 9000:9000 mitmproxy/mitmproxy mitmproxy -p 9000

  # mix test test/integration --include skip

  defmodule PlainServerPlug do
    import Plug.Conn
    def init(options), do: options
    def call(conn, _), do: send_resp(conn, 200, "hi, there")
  end

  test "Make HTTP request through proxy" do
    {:ok, _} = Plug.Adapters.Cowboy2.http(PlainServerPlug, [], port: 8886)

    System.put_env("NEW_RELIC_PROXY_URL", "http://localhost:9000")

    try do
      {:ok, %{body: body}} = NewRelic.Util.Http.post("http://localhost:8886", "", [])
      assert body == "hi, there"
    after
      System.delete_env("NEW_RELIC_PROXY_URL")
    end
  end
end
