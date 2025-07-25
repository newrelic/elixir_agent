defmodule NewRelic.Error.Reporter.ErrorMsg do
  @moduledoc false

  alias NewRelic.Util
  alias NewRelic.Harvest.Collector

  def report_error(:transaction, report) do
    {exception, stacktrace} =
      case report.reason do
        {{{exception, _innner_stacktrace}, _initial_call}, stacktrace} -> {exception, stacktrace}
        {exception, stacktrace} -> {exception, stacktrace}
      end

    process_name = parse_process_name(report[:registered_name], stacktrace)

    NewRelic.add_attributes("error.process": process_name)

    NewRelic.Transaction.Reporter.error(%{
      kind: :error,
      reason: exception,
      stack: stacktrace
    })
  end

  def report_error(:process, report) do
    {exception_type, reason, stacktrace, expected} = parse_reason(report.reason)

    process_name = parse_process_name(report[:registered_name], stacktrace)
    automatic_attributes = NewRelic.Config.automatic_attributes()
    formatted_stacktrace = Util.Error.format_stacktrace(stacktrace, nil)

    Collector.ErrorTrace.Harvester.report_error(%NewRelic.Error.Trace{
      timestamp: System.system_time(:millisecond) / 1_000,
      error_type: exception_type,
      message: reason,
      expected: expected,
      stack_trace: formatted_stacktrace,
      transaction_name: "OtherTransaction/Elixir/ElixirProcess//#{process_name}",
      user_attributes:
        Map.merge(automatic_attributes, %{
          process: process_name
        })
    })

    Collector.TransactionErrorEvent.Harvester.report_error(%NewRelic.Error.Event{
      timestamp: System.system_time(:millisecond) / 1_000,
      error_class: exception_type,
      error_message: reason,
      expected: expected,
      transaction_name: "OtherTransaction/Elixir/ElixirProcess//#{process_name}",
      user_attributes:
        Map.merge(automatic_attributes, %{
          process: process_name,
          stacktrace: Enum.join(formatted_stacktrace, "\n")
        })
    })

    unless expected do
      NewRelic.report_metric({:supportability, :error_event}, error_count: 1)
      NewRelic.report_metric(:error, error_count: 1)
    end
  end

  defp parse_reason({%type{message: message} = exception, stacktrace}) do
    expected = parse_error_expected(exception)
    type = inspect(type)
    reason = "(#{type}) #{message}"

    {type, reason, stacktrace, expected}
  end

  defp parse_reason({exception, stacktrace}) do
    exception = Exception.normalize(:error, exception, stacktrace)
    type = inspect(exception.__struct__)
    message = Exception.message(exception)
    reason = "(#{type}) #{message}"

    {type, reason, stacktrace, false}
  end

  defp parse_process_name([], [{module, _f, _a, _} | _]), do: inspect(module)
  defp parse_process_name([], _stacktrace), do: "UnknownProcess"
  defp parse_process_name(nil, _stacktrace), do: "UnknownProcess"
  defp parse_process_name(registered_name, _stacktrace), do: inspect(registered_name)

  defp parse_error_expected(%{expected: true}), do: true
  defp parse_error_expected(_), do: false
end
