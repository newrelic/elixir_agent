defmodule EctoExample.SQLite3Repo do
  use Ecto.Repo,
    otp_app: :ecto_example,
    adapter: Ecto.Adapters.SQLite3
end
