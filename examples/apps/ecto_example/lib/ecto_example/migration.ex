defmodule EctoExample.Migration do
  use Ecto.Migration

  def up do
    create table("counts") do
      timestamps()
    end

    # used to trigger an Error in router
    create(index(:counts, :inserted_at, unique: true))
  end
end
