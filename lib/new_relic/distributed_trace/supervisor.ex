defmodule NewRelic.DistributedTrace.Supervisor do
  use Supervisor

  @moduledoc false

  def start_link(_) do
    Supervisor.start_link(__MODULE__, [])
  end

  def init(_) do
    children = [
      NewRelic.DistributedTrace.BackoffSampler
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
