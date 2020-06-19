defmodule NewRelic.Sampler.Supervisor do
  use Supervisor

  @moduledoc false

  def start_link(_) do
    Supervisor.start_link(__MODULE__, [])
  end

  def init(_) do
    children = [
      NewRelic.Sampler.Agent,
      NewRelic.Sampler.Beam,
      NewRelic.Sampler.Process,
      NewRelic.Sampler.TopProcess,
      NewRelic.Sampler.Ets
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
