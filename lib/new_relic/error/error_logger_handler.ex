defmodule NewRelic.Error.ErrorLoggerHandler do
  @behaviour :gen_event
  @moduledoc false

  # http://erlang.org/doc/man/error_logger.html

  def add_handler() do
    :error_logger.delete_report_handler(NewRelic.Error.ErrorLoggerHandler)
    :error_logger.add_report_handler(NewRelic.Error.ErrorLoggerHandler)
  end

  def remove_handler() do
    :error_logger.delete_report_handler(NewRelic.Error.ErrorLoggerHandler)
  end

  def init(args) do
    NewRelic.sample_process()
    {:ok, args}
  end

  def handle_info(_msg, state), do: {:ok, state}
  def handle_call(request, _state), do: exit({:bad_call, request})
  def code_change(_old_vsn, state, _extra), do: {:ok, state}
  def terminate(_reason, _state), do: :ok

  def handle_event({_type, gl, _report}, state)
      when node(gl) != node() do
    {:ok, state}
  end

  def handle_event({:error_report, _gl, {pid, :crash_report, [report | _]}}, state)
      when is_list(report) do
    if NewRelic.Transaction.Reporter.tracking?(pid) do
      NewRelic.Error.Reporter.report_error(:transaction, report)
    else
      Task.Supervisor.start_child(NewRelic.Error.TaskSupervisor, fn ->
        NewRelic.Error.Reporter.report_error(:process, report)
      end)
    end

    {:ok, state}
  end

  def handle_event(_, state), do: {:ok, state}
end
