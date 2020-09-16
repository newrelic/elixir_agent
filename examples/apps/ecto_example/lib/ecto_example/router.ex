defmodule EctoExample.Router do
  use Plug.Router
  use NewRelic.Transaction

  plug(:match)
  plug(:dispatch)

  get "/hello" do
    error_query(EctoExample.PostgresRepo)
    error_query(EctoExample.MySQLRepo)
    error_query(EctoExample.MsSQLRepo)

    count_query(EctoExample.PostgresRepo)
    count_query(EctoExample.MySQLRepo)
    count_query(EctoExample.MsSQLRepo)

    stream_query(EctoExample.PostgresRepo)
    stream_query(EctoExample.MySQLRepo)
    stream_query(EctoExample.MsSQLRepo)

    delete_query(EctoExample.PostgresRepo)
    delete_query(EctoExample.MySQLRepo)
    delete_query(EctoExample.MsSQLRepo)

    send_resp(conn, 200, Jason.encode!(%{hello: "world"}))
  end

  match _ do
    send_resp(conn, 404, "oops")
  end

  def stream_query(repo) do
    repo.transaction(fn ->
      EctoExample.Count.all()
      |> repo.stream()
      |> Enum.to_list()
    end)
    |> case do
      {:ok, [_ | _]} -> :good
    end
  end

  def delete_query(repo) do
    repo.get!(EctoExample.Count, 1)
    |> repo.delete!
  end

  def count_query(repo) do
    {:ok, %{id: id}} = repo.insert(%EctoExample.Count{})
    record = repo.get!(EctoExample.Count, id) |> Ecto.Changeset.change()
    repo.update!(record, force: true)

    repo.aggregate(EctoExample.Count, :count)
    |> case do
      n when n > 1 -> :good
    end
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
