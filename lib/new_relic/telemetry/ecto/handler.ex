defmodule NewRelic.Telemetry.Ecto.Handler do
  @moduledoc false

  alias NewRelic.Telemetry.Ecto.Metadata

  def handle_event(
        _event,
        %{total_time: total_time} = measurements,
        %{type: :ecto_sql_query, repo: repo} = metadata,
        config
      ) do
    end_time = System.system_time(:microsecond) / 1000

    duration_ms = total_time |> to_ms
    duration_s = duration_ms / 1000
    start_time = end_time - duration_ms

    query_time_ms = measurements[:query_time] |> to_ms
    queue_time_ms = measurements[:queue_time] |> to_ms
    decode_time_ms = measurements[:decode_time] |> to_ms

    database = config.opts[:database] || "unknown"
    hostname = config.opts[:hostname] || "unknown"
    port = config.opts[:port] || "unknown"

    query = (config.collect_db_query? && metadata.query) || "[NOT_COLLECTED]"

    pid = inspect(self())
    id = {:ecto_sql_query, make_ref()}
    parent_id = Process.get(:nr_current_span) || :root

    with {datastore, {operation, table}} <- Metadata.parse(metadata) do
      metric_name = "Datastore/statement/#{datastore}/#{table}/#{operation}"
      secondary_name = "#{inspect(repo)} #{hostname}:#{port}/#{database}"

      NewRelic.Transaction.Reporter.add_trace_segment(%{
        primary_name: metric_name,
        secondary_name: secondary_name,
        attributes: %{
          sql: query,
          collection: table,
          operation: operation,
          host: hostname,
          database_name: database,
          port_path_or_id: port |> to_string
        },
        pid: pid,
        id: id,
        parent_id: parent_id,
        start_time: start_time,
        end_time: end_time
      })

      NewRelic.report_span(
        timestamp_ms: start_time,
        duration_s: duration_s,
        name: metric_name,
        edge: [span: id, parent: parent_id],
        category: "datastore",
        attributes:
          %{
            component: datastore,
            "span.kind": :client,
            "db.statement": query,
            "db.instance": database,
            "peer.address": "#{hostname}:#{port}}",
            "peer.hostname": hostname,
            "db.table": table,
            "db.operation": operation,
            "ecto.repo": inspect(repo)
          }
          |> maybe_add("ecto.query_time.ms", query_time_ms)
          |> maybe_add("ecto.queue_time.ms", queue_time_ms)
          |> maybe_add("ecto.decode_time.ms", decode_time_ms)
      )

      NewRelic.report_metric(
        {:datastore, datastore, table, operation},
        duration_s: duration_s
      )

      NewRelic.Transaction.Reporter.track_metric({
        {:datastore, datastore, table, operation},
        duration_s: duration_s
      })

      NewRelic.incr_attributes(
        databaseCallCount: 1,
        databaseDuration: duration_s,
        datastore_call_count: 1,
        datastore_duration_ms: duration_ms
      )

      if NewRelic.Config.feature?(:extended_attributes) do
        NewRelic.incr_attributes(
          "datastore.#{table}.call_count": 1,
          "datastore.#{table}.duration_ms": duration_ms
        )
      end
    end
  end

  def handle_event(_event, _value, _metadata, _config) do
    :ignore
  end

  defp to_ms(nil), do: nil
  defp to_ms(ns), do: System.convert_time_unit(ns, :nanosecond, :microsecond) / 1000

  defp maybe_add(map, _, nil), do: map
  defp maybe_add(map, key, value), do: Map.put(map, key, value)
end
