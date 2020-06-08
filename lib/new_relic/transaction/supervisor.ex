defmodule NewRelic.Transaction.Supervisor do
  use Supervisor

  @moduledoc false

  def start_link do
    Supervisor.start_link(__MODULE__, [])
  end

  def init(_) do
    children = [
      supervisor(Task.Supervisor, [[name: NewRelic.Transaction.TaskSupervisor]]),
      worker(NewRelic.Transaction.ErlangTrace, []),
      supervisor(NewRelic.Transaction.SidecarSupervisor, []),
      worker(
        Registry,
        [
          [
            keys: :unique,
            name: NewRelic.Transaction.Registry,
            partitions: System.schedulers_online()
          ]
        ]
      )
    ]

    supervise(children, strategy: :one_for_one)
  end
end
