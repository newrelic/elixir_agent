defmodule NewRelic.Telemetry.Redix do
  use GenServer

  @moduledoc """
  Provides `Redix` instrumentation via `telemetry`.

  Redix connections are auto-discovered and instrumented.

  We automatically gather:

  * Datastore metrics
  * Transaction Trace segments
  * Transaction datastore attributes
  * Distributed Trace span events

  You can opt-out of this instrumentation as a whole with `:redix_instrumentation_enabled`
  and specifically of query collection with `:query_collection_enabled` via configuration.
  See `NewRelic.Config` for details.
  """

  @doc false
  def start_link(_) do
    enabled = NewRelic.Config.feature?(:redix_instrumentation)
    GenServer.start_link(__MODULE__, [enabled: enabled], name: __MODULE__)
  end

  @redix_connection [:redix, :connection]
  @redix_pipeline_stop [:redix, :pipeline, :stop]

  @init_events [@redix_connection]
  @connected_events [@redix_connection, @redix_pipeline_stop]

  @doc false
  def init(enabled: false), do: :ignore

  def init(enabled: true) do
    config = %{
      handler_id: {:new_relic, :redix},
      connections: %{},
      collect_db_query?: NewRelic.Config.feature?(:query_collection)
    }

    :telemetry.attach_many(
      config.handler_id,
      @init_events,
      &__MODULE__.handle_event/4,
      config
    )

    Process.flag(:trap_exit, true)
    {:ok, config}
  end

  def handle_call({@redix_connection, meta}, _from, config) do
    [host, port] = meta.address |> String.split(":")

    config =
      update_in(
        config.connections,
        &Map.put(
          &1,
          meta[:connection_name] || meta[:connection],
          %{address: meta.address, host: host, port: port}
        )
      )

    :telemetry.detach(config.handler_id)

    :telemetry.attach_many(
      config.handler_id,
      @connected_events,
      &__MODULE__.handle_event/4,
      config
    )

    {:reply, :ok, config}
  end

  def terminate(_reason, %{handler_id: handler_id}) do
    :telemetry.detach(handler_id)
  end

  @doc false
  def handle_event(@redix_connection, _, meta, _config) do
    GenServer.call(__MODULE__, {@redix_connection, meta})
  end

  def handle_event(
        @redix_pipeline_stop,
        %{duration: duration},
        %{commands: commands} = meta,
        config
      ) do
    end_time_ms = System.system_time(:microsecond) / 1000
    duration_ms = System.convert_time_unit(duration, :native, :microsecond) / 1000
    duration_s = duration_ms / 1000
    start_time_ms = end_time_ms - duration_ms

    datastore = "Redis"
    {operation, query} = parse_command(commands, collect: config.collect_db_query?)
    connection = meta[:connection_name] || meta[:connection]

    pid = inspect(self())
    id = {:redix, make_ref()}
    parent_id = Process.get(:nr_current_span) || :root

    instance = config.connections[connection] || %{}

    address = instance[:address] || "unknown"
    hostname = instance[:host] || "unknown"
    port = instance[:port] || "unknown"

    metric_name = "Datastore/operation/#{datastore}/#{operation}"
    secondary_name = "#{inspect(connection)} #{address}"

    NewRelic.Transaction.Reporter.add_trace_segment(%{
      primary_name: metric_name,
      secondary_name: secondary_name,
      attributes: %{
        sql: query,
        operation: operation,
        host: hostname,
        port_path_or_id: port
      },
      pid: pid,
      id: id,
      parent_id: parent_id,
      start_time: start_time_ms,
      end_time: end_time_ms
    })

    NewRelic.report_span(
      timestamp_ms: start_time_ms,
      duration_s: duration_s,
      name: metric_name,
      edge: [span: id, parent: parent_id],
      category: "datastore",
      attributes:
        %{
          component: datastore,
          "span.kind": :client,
          "db.statement": query,
          "peer.address": address,
          "peer.hostname": hostname,
          "db.operation": operation
        }
        |> maybe_add(:"redix.error", meta[:reason])
        |> maybe_add(:"redix.connection", meta[:connection])
        |> maybe_add(:"redix.connection_name", meta[:connection_name])
    )

    NewRelic.report_metric({:datastore, datastore, operation}, duration_s: duration_s)

    NewRelic.Transaction.Reporter.track_metric({
      {:datastore, datastore, operation},
      duration_s: duration_s
    })

    NewRelic.incr_attributes(
      databaseCallCount: 1,
      databaseDuration: duration_s,
      datastore_call_count: 1,
      datastore_duration_ms: duration_ms
    )
  end

  def handle_event(_event, _measurements, _meta, _config) do
    :ignore
  end

  @not_collected "[NOT_COLLECTED]"
  defp parse_command([[operation | _args] = command], collect: true) do
    query = Enum.join(command, " ")
    {operation, query}
  end

  defp parse_command([[operation | _args]], collect: false) do
    {operation, @not_collected}
  end

  defp parse_command(pipeline, collect: true) do
    query = pipeline |> Enum.map(&Enum.join(&1, " ")) |> Enum.join("; ")
    {"PIPELINE", query}
  end

  defp parse_command(_pipeline, collect: false) do
    {"PIPELINE", @not_collected}
  end

  defp maybe_add(map, _, nil), do: map

  defp maybe_add(map, key, %{__exception__: true} = value),
    do: Map.put(map, key, Exception.message(value))

  defp maybe_add(map, key, value), do: Map.put(map, key, inspect(value))
end
