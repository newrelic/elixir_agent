defmodule EctoExample.Router do
  use Plug.Router
  use NewRelic.Transaction
  use NewRelic.Tracer

  plug(:match)
  plug(:dispatch)

  get "/hello" do
    response =
      %{
        hello: "world",
        postgres_count: query_db(EctoExample.PostgresRepo),
        mysql_count: query_db(EctoExample.MySQLRepo)
      }
      |> Jason.encode!()

    Process.sleep(100)
    send_resp(conn, 200, response)
  end

  match _ do
    send_resp(conn, 404, "oops")
  end

  @trace :query_db
  def query_db(repo) do
    {:ok, _} = repo.insert(%EctoExample.Count{})
    Process.sleep(20)
    repo.aggregate(EctoExample.Count, :count)
  end
end
