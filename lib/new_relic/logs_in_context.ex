defmodule NewRelic.LogsInContext do
  @moduledoc false

  alias NewRelic.Harvest.Collector.AgentRun
  alias NewRelic.Harvest.TelemetrySdk

  def configure(:direct) do
    :logger.add_primary_filter(:nr_logs_in_context, {&primary_filter/2, %{mode: :direct}})
  end

  def configure(:forwarder) do
    :logger.add_primary_filter(:nr_logs_in_context, {&primary_filter/2, %{mode: :forwarder}})
    configure_log_output()
  end

  def configure(:disabled) do
    :skip
  end

  def configure(unknown) do
    NewRelic.log(:error, "Unknown :logs_in_context mode: #{inspect(unknown)}")
    :skip
  end

  if NewRelic.Util.ConditionalCompile.match?(">= 1.15.0") do
    defp configure_log_output do
      :logger.update_handler_config(:default, :formatter, Logger.Formatter.new(format: "$message\n"))
    end
  else
    defp configure_log_output do
      Logger.configure_backend(:console, format: {NewRelic.LogsInContext, :format})
    end

    def format(_level, message, _timestamp, _metadata) when is_binary(message) do
      message <> "\n"
    end

    def format(level, message, timestamp, metadata) do
      config = Logger.Formatter.compile(nil)
      Logger.Formatter.format(config, level, message, timestamp, metadata)
    end
  end

  defp primary_filter(%{msg: {:string, msg}} = log, %{mode: :direct}) do
    [message: IO.iodata_to_binary(msg)]
    |> prepare_log(log)
    |> TelemetrySdk.Logs.Harvester.report_log()

    :ignore
  end

  defp primary_filter(%{msg: {:report, report}, meta: %{domain: [:elixir]}} = log, %{mode: :direct}) do
    report
    |> prepare_log(log)
    |> TelemetrySdk.Logs.Harvester.report_log()

    :ignore
  end

  defp primary_filter(%{msg: {:string, msg}} = log, %{mode: :forwarder}) do
    message =
      [message: IO.iodata_to_binary(msg)]
      |> prepare_log(log)
      |> Map.merge(linking_metadata())
      |> NewRelic.JSON.encode!()

    %{log | msg: {:string, message}}
  end

  defp primary_filter(%{msg: {:report, report}, meta: %{domain: [:elixir]}} = log, %{mode: :forwarder}) do
    message =
      report
      |> prepare_log(log)
      |> Map.merge(linking_metadata())
      |> NewRelic.JSON.encode!()

    %{log | msg: {:string, message}}
  end

  defp primary_filter(_log, _config) do
    :ignore
  end

  defp prepare_log(metadata, log) do
    Map.new(metadata)
    |> Map.merge(log_metadata(log))
    |> Map.merge(custom_metadata(log))
    |> Map.merge(tracing_metadata())
  end

  defp log_metadata(log) do
    meta_attributes =
      case log.meta do
        %{mfa: {m, f, a}, file: file, line: line} ->
          %{
            "file.name": to_string(file),
            "line.number": line,
            "module.name": inspect(m),
            "function.name": "#{f}/#{a}"
          }

        _ ->
          %{}
      end

    %{
      timestamp: System.convert_time_unit(log.meta.time, :microsecond, :millisecond),
      "log.level": log.level,
      "process.pid": inspect(log.meta.pid)
    }
    |> Map.merge(meta_attributes)
  end

  @ignored [:domain, :file, :gl, :line, :mfa, :pid, :time]
  defp custom_metadata(log) do
    [metadata: Map.drop(log.meta, @ignored)]
    |> NewRelic.Util.deep_flatten()
    |> NewRelic.Util.coerce_attributes()
    |> Map.new()
    |> Map.delete("metadata.size")
  end

  def linking_metadata() do
    AgentRun.entity_metadata()
  end

  defp tracing_metadata() do
    context = NewRelic.DistributedTrace.get_tracing_context() || %{}

    %{
      "trace.id": Map.get(context, :trace_id),
      "span.id": Map.get(context, :guid)
    }
  end
end
