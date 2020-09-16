defmodule EctoExample.Database do
  use GenServer

  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok)
  end

  def init(:ok) do
    start_and_migrate(EctoExample.PostgresRepo, Ecto.Adapters.Postgres)
    start_and_migrate(EctoExample.MySQLRepo, Ecto.Adapters.MyXQL)
    start_and_migrate(EctoExample.MsSQLRepo, Ecto.Adapters.TDS)

    {:ok, %{}}
  end

  def start_and_migrate(repo, adapter) do
    config = Application.get_env(:ecto_example, repo)

    adapter.storage_down(config)
    :ok = adapter.storage_up(config)

    repo.start_link()
    Ecto.Migrator.up(repo, 0, EctoExample.Migration)
  end
end
