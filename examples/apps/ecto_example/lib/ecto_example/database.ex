defmodule EctoExample.Database do
  use GenServer

  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok)
  end

  def init(:ok) do
    start_and_migrate(EctoExample.PostgresRepo)
    start_and_migrate(EctoExample.MySQLRepo)
    start_and_migrate(EctoExample.SQLite3Repo)

    {:ok, %{}}
  end

  def start_and_migrate(repo) do
    config = Application.get_env(:ecto_example, repo)

    adapter = repo.__adapter__()
    adapter.storage_down(config)
    :ok = adapter.storage_up(config)

    repo.start_link()
    Ecto.Migrator.up(repo, 0, EctoExample.Migration)
  end
end
