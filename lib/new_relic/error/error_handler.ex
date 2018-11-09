defmodule NewRelic.Error.ErrorHandler do
  @behaviour :gen_event

  # This event handler gets installed as an Error Logger, which
  # receives messages when error events are logged.
  # http://erlang.org/doc/man/error_logger.html

  @moduledoc false

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
      NewRelic.Error.Reporter.report_transaction_error(report)
    else
      Task.Supervisor.start_child(NewRelic.Error.TaskSupervisor, fn ->
        NewRelic.Error.Reporter.report_process_error(report)
      end)
    end

    {:ok, state}
  end

  def handle_event(_, state), do: {:ok, state}
end
