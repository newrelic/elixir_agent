defmodule NewRelic.Transaction.ErlangTraceSupervisor do
  use Supervisor

  @moduledoc false

  def start_link(_) do
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_) do
    children = [
      NewRelic.Transaction.ErlangTrace
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
