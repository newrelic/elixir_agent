defmodule NewRelic.EnabledSupervisor do
  use Supervisor

  # This Supervisor starts processes that we
  # only start if the agent is enabled

  @moduledoc false

  def start_link() do
    NewRelic.Harvest.Collector.AgentRun.ensure_init()
    start_link(enabled: NewRelic.Config.enabled?())
  end

  def start_link(enabled: enabled) do
    Supervisor.start_link(__MODULE__, enabled: enabled)
  end

  def init(enabled: false) do
    :ignore
  end

  def init(enabled: true) do
    children = [
      supervisor(NewRelic.Harvest.Supervisor, []),
      supervisor(NewRelic.Sampler.Supervisor, []),
      supervisor(NewRelic.Error.Supervisor, []),
      supervisor(NewRelic.Aggregate.Supervisor, [])
    ]

    supervise(children, strategy: :one_for_one)
  end
end
