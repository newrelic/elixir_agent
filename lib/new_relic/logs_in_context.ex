defmodule NewRelic.LogsInContext do
  @moduledoc false

  alias NewRelic.Harvest.Collector.AgentRun

  def primary_filter(%{msg: {:string, msg}} = log, _config) do
    message =
      %{
        message: msg,
        timestamp: System.convert_time_unit(log.meta.time, :microsecond, :millisecond),
        "log.level": log.level
      }
      |> Map.merge(log_metadata(log))
      |> Map.merge(logger_metadata())
      |> Map.merge(linking_metadata())
      |> Jason.encode!()

    %{log | msg: {:string, message}}
  end

  def primary_filter(_log, _config) do
    :ignore
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

  defp logger_metadata() do
    case :logger.get_process_metadata() do
      :undefined ->
        %{}

      metadata ->
        [metadata: metadata]
        |> NewRelic.Util.deep_flatten()
        |> NewRelic.Util.coerce_attributes()
        |> Map.new()
    end
  end

  defp linking_metadata() do
    context = NewRelic.DistributedTrace.get_tracing_context() || %{}

    Map.merge(
      AgentRun.entity_metadata(),
      %{
        "trace.id": Map.get(context, :trace_id),
        "span.id": Map.get(context, :guid)
      }
    )
  end

  def format(_level, message, _timestamp, _metadata) when is_binary(message) do
    message <> "\n"
  end

  # Fallback to default formatter for future compatibility with Elixir structured logging
  def format(level, message, timestamp, metadata) do
    config = Logger.Formatter.compile(nil)
    Logger.Formatter.format(config, level, message, timestamp, metadata)
  end
end
