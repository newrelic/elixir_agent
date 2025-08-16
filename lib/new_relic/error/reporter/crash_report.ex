defmodule NewRelic.Error.Reporter.CrashReport do
  @moduledoc false

  alias NewRelic.Util
  alias NewRelic.Harvest.Collector

  # Don't report exceptions that result in a 400 level response
  def report_error(_, [
        {:initial_call, _},
        {:pid, _},
        {:registered_name, _},
        {:error_info, {:exit, {{{%{plug_status: plug_status}, _plug_stack}, _init_call}, _}, _}}
        | _
      ])
      when plug_status < 500 do
    :ignore
  end

  # Don't double report exceptions re-raised by PlugCowboy
  def report_error(_, [
        {:initial_call, {:cowboy_stream_h, :request_process, _}},
        {:pid, _},
        {:registered_name, _},
        {:error_info, {:exit, {_, [{Plug.Cowboy.Handler, :exit_on_error, _, _} | _]}, _}}
        | _
      ]) do
    :ignore
  end

  def report_error(:transaction, report) do
    {kind, exception, stacktrace} = parse_error_info(report[:error_info])
    process_name = parse_process_name(report[:registered_name], stacktrace)

    NewRelic.add_attributes("error.process": process_name)

    NewRelic.Transaction.Reporter.error(%{
      kind: kind,
      reason: exception,
      stack: stacktrace
    })
  end

  def report_error(:process, report) do
    {kind, exception, stacktrace} = parse_error_info(report[:error_info])
    already_reported? = {kind, exception, List.first(stacktrace)} == report[:dictionary][:nr_error_explicitly_reported]

    if already_reported? do
      :ignore
    else
      {exception_type, exception_reason, exception_stacktrace} =
        Util.Error.normalize(kind, exception, stacktrace, report[:initial_call])

      process_name = parse_process_name(report[:registered_name], stacktrace)
      expected = parse_error_expected(exception)
      automatic_attributes = NewRelic.Config.automatic_attributes()

      Collector.ErrorTrace.Harvester.report_error(%NewRelic.Error.Trace{
        timestamp: System.system_time(:millisecond) / 1_000,
        error_type: exception_type,
        message: exception_reason,
        expected: expected,
        stack_trace: exception_stacktrace,
        transaction_name: "OtherTransaction/Elixir/ElixirProcess//#{process_name}",
        user_attributes:
          Map.merge(automatic_attributes, %{
            process: process_name
          })
      })

      Collector.TransactionErrorEvent.Harvester.report_error(%NewRelic.Error.Event{
        timestamp: System.system_time(:millisecond) / 1_000,
        error_class: exception_type,
        error_message: exception_reason,
        expected: expected,
        transaction_name: "OtherTransaction/Elixir/ElixirProcess//#{process_name}",
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
  end

  defp parse_process_name([], [{module, _f, _a, _} | _]), do: inspect(module)
  defp parse_process_name([], _stacktrace), do: "UnknownProcess"
  defp parse_process_name(registered_name, _stacktrace), do: inspect(registered_name)

  defguard is_mfa(value) when is_tuple(value) and tuple_size(value) == 3

  defp parse_error_info({kind, {{{exception, call}, init_call}, _init_stack}, _proc_stack})
       when is_mfa(call) and is_mfa(init_call) do
    {kind, exception, [parse_call(call), parse_call(init_call)]}
  end

  defp parse_error_info({kind, {{{exception, stacktrace}, _init_call}, _init_stack}, _proc_stack}) do
    {kind, exception, stacktrace}
  end

  defp parse_error_info({kind, {exception, stacktrace}, _stack}) when is_list(stacktrace) do
    {kind, exception, stacktrace}
  end

  defp parse_error_info({kind, exception, stacktrace}) do
    {kind, exception, stacktrace}
  end

  defp parse_call({m, f, a}), do: {m, f, length(a), []}

  defp parse_error_expected(%{expected: true}), do: true
  defp parse_error_expected(_), do: false
end
