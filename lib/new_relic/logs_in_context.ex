defmodule NewRelic.LogsInContext do
  @moduledoc false

  alias NewRelic.Harvest.Collector.AgentRun
  alias NewRelic.Harvest.TelemetrySdk

  @elixir_version_requirement ">= 1.10.0"
  def elixir_version_supported?(mode) do
    case Version.match?(System.version(), @elixir_version_requirement) do
      true ->
        true

      false ->
        mode in [:direct, :forwarder] &&
          NewRelic.log(:error, ":logs_in_context requires Elixir 1.10 or greater")

        false
    end
  end

  def configure(:direct) do
    :logger.add_primary_filter(:nr_logs_in_context, {&primary_filter/2, %{mode: :direct}})
  end

  def configure(:forwarder) do
    :logger.add_primary_filter(:nr_logs_in_context, {&primary_filter/2, %{mode: :forwarder}})
    Logger.configure_backend(:console, format: {NewRelic.LogsInContext, :format})
  end

  def configure(:disabled) do
    :skip
  end

  def configure(unknown) do
    NewRelic.log(:error, "Unknown :logs_in_context mode: #{inspect(unknown)}")
    :skip
  end

  def primary_filter(%{msg: {:string, _msg}} = log, %{mode: :direct}) do
    log
    |> prepare_log()
    |> TelemetrySdk.Logs.Harvester.report_log()

    log
  end

  def primary_filter(%{msg: {:string, _msg}} = log, %{mode: :forwarder}) do
    message =
      log
      |> prepare_log()
      |> Map.merge(linking_metadata())
      |> Jason.encode!()

    %{log | msg: {:string, message}}
  end

  def primary_filter(_log, _config) do
    :ignore
  end

  defp prepare_log(%{msg: {:string, msg}} = log) do
    %{
      message: IO.iodata_to_binary(msg),
      timestamp: System.convert_time_unit(log.meta.time, :microsecond, :millisecond),
      "log.level": log.level
    }
    |> Map.merge(log_metadata(log))
    |> Map.merge(custom_metadata(log))
    |> Map.merge(tracing_metadata())
  end

  def format(_level, message, _timestamp, _metadata) when is_binary(message) do
    message <> "\n"
  end

  # Fallback to default formatter for future compatibility with Elixir structured logging
  def format(level, message, timestamp, metadata) do
    config = Logger.Formatter.compile(nil)
    Logger.Formatter.format(config, level, message, timestamp, metadata)
  end

  defp log_metadata(log) do
    {module, function, arity} = log.meta.mfa

    %{
      "line.number": log.meta.line,
      "file.name": log.meta.file |> to_string,
      "module.name": inspect(module),
      "function.name": "#{function}/#{arity}",
      "process.pid": inspect(log.meta.pid)
    }
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

  def tracing_metadata() do
    context = NewRelic.DistributedTrace.get_tracing_context() || %{}

    %{
      "trace.id": Map.get(context, :trace_id),
      "span.id": Map.get(context, :guid)
    }
  end
end
