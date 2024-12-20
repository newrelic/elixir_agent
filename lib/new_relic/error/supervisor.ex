defmodule NewRelic.Error.Supervisor do
  use Supervisor
  alias NewRelic.Error

  # Registers an erlang error logger to catch and report errors.

  @moduledoc false

  def start_link(_) do
    Supervisor.start_link(__MODULE__, [])
  end

  def init(_) do
    children = [
      {Task.Supervisor, name: Error.TaskSupervisor}
    ]

    if NewRelic.Config.feature?(:error_collector) do
      add_filter()
    end

    Supervisor.init(children, strategy: :one_for_one)
  end

  def add_filter(),
    do: NewRelic.Error.LoggerFilter.add_filter()

  def remove_filter(),
    do: NewRelic.Error.LoggerFilter.remove_filter()
end
