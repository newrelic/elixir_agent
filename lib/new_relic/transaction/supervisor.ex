defmodule NewRelic.Transaction.Supervisor do
  use Supervisor

  @moduledoc false

  def start_link(_) do
    Supervisor.start_link(__MODULE__, [])
  end

  def init(_) do
    children = [
      {Task.Supervisor, name: NewRelic.Transaction.TaskSupervisor},
      NewRelic.Transaction.Monitor,
      NewRelic.Transaction.Reporter
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
