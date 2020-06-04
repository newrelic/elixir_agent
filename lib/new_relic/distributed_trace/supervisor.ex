defmodule NewRelic.DistributedTrace.Supervisor do
  use Supervisor

  @moduledoc false

  def start_link do
    Supervisor.start_link(__MODULE__, [])
  end

  def init(_) do
    children = [
      worker(NewRelic.DistributedTrace.BackoffSampler, [])
    ]

    supervise(children, strategy: :one_for_one)
  end
end
