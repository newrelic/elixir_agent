defmodule RedixExample.Router do
  use Plug.Router
  use NewRelic.Transaction

  plug(:match)
  plug(:dispatch)

  get "/hello" do
    {:ok, _} = Redix.command(:redix, ["SET", "mykey", "foo"])
    {:ok, "foo"} = Redix.command(:redix, ["GET", "mykey"])

    {:ok, [_, _, _, "2"]} =
      Redix.pipeline(:redix, [
        ["DEL", "counter"],
        ["INCR", "counter"],
        ["INCR", "counter"],
        ["GET", "counter"]
      ])

    send_resp(conn, 200, Jason.encode!(%{hello: "world"}))
  end

  match _ do
    send_resp(conn, 404, "oops")
  end
end
