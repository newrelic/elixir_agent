defmodule NewRelic.Application do
  use Application

  @moduledoc false

  def start(_type, _args) do
    import Supervisor.Spec

    NewRelic.Init.run()

    children = [
      worker(NewRelic.Logger, []),
      supervisor(NewRelic.Harvest.Supervisor, []),
      supervisor(NewRelic.Sampler.Supervisor, []),
      supervisor(NewRelic.Transaction.Supervisor, []),
      supervisor(NewRelic.DistributedTrace.Supervisor, []),
      supervisor(NewRelic.Aggregate.Supervisor, [])
    ]

    children =
      if NewRelic.Config.error_reporting_enabled?() do
        children ++ [supervisor(NewRelic.Error.Supervisor, [])]
      else
        children
      end

    opts = [strategy: :one_for_one, name: NewRelic.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
