defmodule NewRelic.Transaction.SidecarStore do
  use Supervisor

  @moduledoc false

  def start_link(_) do
    Supervisor.start_link(__MODULE__, :ok)
  end

  def init(:ok) do
    NewRelic.Transaction.Sidecar.setup_stores()
    Supervisor.init([], strategy: :one_for_one)
  end
end
