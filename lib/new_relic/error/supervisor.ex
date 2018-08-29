defmodule NewRelic.Error.Supervisor do
  use Supervisor

  # Registers an erlang error logger to catch and report errors.

  @moduledoc false

  def start_link do
    Supervisor.start_link(__MODULE__, [])
  end

  def init(_) do
    children = [
      supervisor(Task.Supervisor, [[name: NewRelic.Error.TaskSupervisor]])
    ]

    :error_logger.delete_report_handler(NewRelic.Error.ErrorHandler)
    :error_logger.add_report_handler(NewRelic.Error.ErrorHandler)
    supervise(children, strategy: :one_for_one)
  end
end
