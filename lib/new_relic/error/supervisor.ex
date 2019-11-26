defmodule NewRelic.Error.Supervisor do
  use Supervisor
  alias NewRelic.Error

  # Registers an erlang error logger to catch and report errors.

  @moduledoc false

  def start_link do
    Supervisor.start_link(__MODULE__, [])
  end

  def init(_) do
    children = [
      supervisor(Task.Supervisor, [[name: Error.TaskSupervisor]])
    ]

    if NewRelic.Config.feature?(:error_collector) do
      add_handler()
    end

    supervise(children, strategy: :one_for_one)
  end

  def add_handler(),
    do: NewRelic.Error.LoggerHandler.add_handler()

  def remove_handler(),
    do: NewRelic.Error.LoggerHandler.remove_handler()
end
