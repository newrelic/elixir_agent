defmodule NewRelic.Error.LoggerFilter do
  @moduledoc false

  # Track errors by attaching a `:logger` primary filter
  # Always returns `:ignore` so we don't actually filter anything

  def add_filter() do
    :logger.add_primary_filter(__MODULE__, {&__MODULE__.filter/2, []})
  end

  def remove_filter() do
    :logger.remove_primary_filter(__MODULE__)
  end

  def filter(
        %{
          meta: %{error_logger: %{type: :crash_report}},
          msg: {:report, %{report: [report | _]}}
        },
        _opts
      ) do
    if NewRelic.Transaction.Sidecar.tracking?() do
      NewRelic.Error.Reporter.CrashReport.report_error(:transaction, report)
    else
      NewRelic.Error.Reporter.CrashReport.report_error(:process, report)
    end

    :ignore
  end

  if NewRelic.Util.ConditionalCompile.match?("< 1.15.0") do
    def filter(
          %{
            meta: %{error_logger: %{tag: :error_msg}},
            msg: {:report, %{label: {_, :terminating}}}
          },
          _opts
        ) do
      :ignore
    end
  end

  def filter(
        %{
          meta: %{error_logger: %{tag: :error_msg}},
          msg: {:report, %{report: %{reason: _} = report}}
        },
        _opts
      ) do
    if NewRelic.Transaction.Sidecar.tracking?() do
      NewRelic.Error.Reporter.ErrorMsg.report_error(:transaction, report)
    else
      NewRelic.Error.Reporter.ErrorMsg.report_error(:process, report)
    end

    :ignore
  end

  def filter(_log, _opts) do
    :ignore
  end
end
