defmodule NewRelic.Error.LoggerHandler do
  @moduledoc false

  def add_handler() do
    Logger.add_translator({__MODULE__, :translator})
  end

  def remove_handler() do
    Logger.remove_translator({__MODULE__, :translator})
  end

  def translator(_level, _message, _timestamp, {_, [report | _]}) when is_list(report) do
    if NewRelic.Transaction.Sidecar.tracking?() do
      NewRelic.Error.Reporter.report_error(:transaction, report)
    else
      NewRelic.Error.Reporter.report_error(:process, report)
    end

    :skip
  end

  def translator(_level, :error, _timestamp, {_, %{args: _, function: _}} = metadata) do
    if NewRelic.Transaction.Sidecar.tracking?() do
      NewRelic.Error.MetadataReporter.report_error(:transaction, metadata)
    else
      NewRelic.Error.MetadataReporter.report_error(:process, metadata)
    end

    :none
  end

  def translator(_level, _message, _timestamp, _metadata), do: :none
end
