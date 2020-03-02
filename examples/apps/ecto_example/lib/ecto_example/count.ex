defmodule EctoExample.Count do
  use Ecto.Schema

  def all do
    import Ecto.Query
    from(c in EctoExample.Count, select: c)
  end

  schema "counts" do
    timestamps()
  end
end
