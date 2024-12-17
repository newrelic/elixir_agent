defmodule NewRelic.LogsInContext.Supervisor do
  use Supervisor

  @moduledoc false

  def start_link(_) do
    Supervisor.start_link(__MODULE__, [])
  end

  def init(_) do
    mode = NewRelic.Config.feature(:logs_in_context)
    NewRelic.LogsInContext.configure(mode)

    Supervisor.init([], strategy: :one_for_one)
  end
end
