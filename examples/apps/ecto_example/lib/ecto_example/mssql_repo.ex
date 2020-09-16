defmodule EctoExample.MsSQLRepo do
  use Ecto.Repo,
    otp_app: :ecto_example,
    adapter: Ecto.Adapters.Tds
end

