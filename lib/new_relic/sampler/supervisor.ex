defmodule NewRelic.Sampler.Supervisor do
  use Supervisor

  @moduledoc false

  def start_link do
    Supervisor.start_link(__MODULE__, [])
  end

  def init(_) do
    children = [
      worker(NewRelic.Sampler.Beam, []),
      worker(NewRelic.Sampler.Process, []),
      worker(NewRelic.Sampler.TopProcess, []),
      worker(NewRelic.Sampler.Ets, [])
    ]

    supervise(children, strategy: :one_for_one)
  end
end
