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

  alias NewRelic.Util
  alias NewRelic.Harvest.Collector
  alias NewRelic.Transaction

  def handle_event({_type, gl, _report}, state)
      when node(gl) != node() do
    {:ok, state}
  end

  def handle_event({:error_report, _gl, {pid, :crash_report, [report | _]}}, state)
      when is_list(report) do
    if Transaction.Reporter.tracking?(pid) do
      report_transaction_error(report)
    else
      Task.Supervisor.start_child(NewRelic.Error.TaskSupervisor, fn ->
        report_process_error(report)
      end)
    end

    {:ok, state}
  end

  def handle_event(_, state), do: {:ok, state}

  def report_transaction_error(report) do
    {kind, exception, stacktrace} = parse_error_info(report[:error_info])
    process_name = parse_process_name(report[:registered_name], stacktrace)

    Transaction.Reporter.set_transaction_error(report[:pid], %{
      kind: kind,
      process: process_name,
      reason: exception,
      stack: stacktrace
    })
  end

  def report_process_error(report) do
    {_kind, exception, stacktrace} = parse_error_info(report[:error_info])

    {exception_type, exception_reason, exception_stacktrace} =
      Util.Error.normalize(exception, stacktrace, report[:initial_call])

    process_name = parse_process_name(report[:registered_name], stacktrace)
    expected = parse_error_expected(exception)
    automatic_attributes = NewRelic.Config.automatic_attributes()

    Collector.ErrorTrace.Harvester.report_error(%NewRelic.Error.Trace{
      timestamp: System.system_time(:milliseconds) / 1_000,
      error_type: inspect(exception_type),
      message: exception_reason,
      expected: expected,
      stack_trace: exception_stacktrace,
      transaction_name: "WebTransaction/Elixir/ElixirProcess//#{process_name}",
      user_attributes:
        Map.merge(automatic_attributes, %{
          process: process_name
        })
    })

    Collector.TransactionErrorEvent.Harvester.report_error(%NewRelic.Error.Event{
      timestamp: System.system_time(:milliseconds) / 1_000,
      error_class: inspect(exception_type),
      error_message: exception_reason,
      expected: expected,
      transaction_name: "WebTransaction/Elixir/ElixirProcess//#{process_name}",
      user_attributes:
        Map.merge(automatic_attributes, %{
          process: process_name,
          stacktrace: Enum.join(exception_stacktrace, "\n")
        })
    })

    unless expected do
      NewRelic.report_metric({:supportability, :error_event}, error_count: 1)
      NewRelic.report_metric(:error, error_count: 1)
    end
  end

  defp parse_process_name([], [{module, _f, _a, _} | _]), do: inspect(module)
  defp parse_process_name([], _stacktrace), do: "UnknownProcess"
  defp parse_process_name(registered_name, _stacktrace), do: inspect(registered_name)

  defp parse_error_info({kind, {exception, stacktrace}, _stack}) when is_list(stacktrace),
    do: {kind, exception, stacktrace}

  defp parse_error_info({kind, exception, stacktrace}), do: {kind, exception, stacktrace}

  defp parse_error_expected(%{expected: true}), do: true
  defp parse_error_expected(_), do: false
end
