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

    error_query(EctoExample.PostgresRepo)
    error_query(EctoExample.MySQLRepo)

    Process.sleep(100)
    send_resp(conn, 200, response)
  end

  match _ do
    send_resp(conn, 404, "oops")
  end

  @trace :query_db
  def query_db(repo) do
    {:ok, %{id: id}} = repo.insert(%EctoExample.Count{})
    record = repo.get!(EctoExample.Count, id) |> Ecto.Changeset.change()
    repo.update!(record, force: true)
    Process.sleep(20)
    repo.aggregate(EctoExample.Count, :count)
  end

  def error_query(repo) do
    # The migration has a unique index on inserted_at
    # This triggers an error that the agent should capture
    ts = ~N[2020-01-17 10:00:00]

    {:ok, %{id: _id}} = repo.insert(%EctoExample.Count{inserted_at: ts})
    {:error, _} = repo.insert(%EctoExample.Count{inserted_at: ts})
  rescue
    Ecto.ConstraintError -> nil
  end
end
