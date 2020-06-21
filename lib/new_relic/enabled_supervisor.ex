defmodule NewRelic.EnabledSupervisor do
  use Supervisor

  # This Supervisor starts processes that we
  # only start if the agent is enabled

  @moduledoc false

  def start_link(_) do
    Supervisor.start_link(__MODULE__, :ok)
  end

  def init(:ok) do
    children = [
      NewRelic.Harvest.Supervisor,
      NewRelic.Sampler.Supervisor,
      NewRelic.Error.Supervisor,
      NewRelic.Aggregate.Supervisor
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
