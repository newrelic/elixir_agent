defmodule EctoExample.PostgresRepo do
  use Ecto.Repo,
    otp_app: :ecto_example,
    adapter: Ecto.Adapters.Postgres
end

defmodule EctoExample.MySQLRepo do
  use Ecto.Repo,
    otp_app: :ecto_example,
    adapter: Ecto.Adapters.MyXQL
end
