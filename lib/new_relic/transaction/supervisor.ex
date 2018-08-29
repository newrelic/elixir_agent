defmodule NewRelic.Transaction.Supervisor do
  use Supervisor

  @moduledoc false

  def start_link do
    Supervisor.start_link(__MODULE__, [])
  end

  def init(_) do
    children = [
      supervisor(Task.Supervisor, [[name: NewRelic.Transaction.TaskSupervisor]]),
      worker(NewRelic.Transaction.Monitor, []),
      worker(NewRelic.Transaction.Reporter, [])
    ]

    supervise(children, strategy: :one_for_one)
  end
end
