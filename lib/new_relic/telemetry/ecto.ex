defmodule NewRelic.Telemetry.Ecto do
  use GenServer

  @moduledoc """
  `NewRelic.Telemetry.Ecto` provides `Ecto` instrumentation via `telemetry`.

  Repos are auto-discovered and instrumented. We automatically gather:

  * Datastore metrics
  * Transaction Trace segments
  * Transaction datastore attributes
  * Distributed Trace span events

  You can opt-out of this instrumentation as a whole and specifically of
  SQL query collection via configuration. See `NewRelic.Config` for details.
  """

  def start_link(otp_app) do
    enabled = NewRelic.Config.feature?(:ecto_instrumentation)
    ecto_repos = Application.get_env(otp_app, :ecto_repos)
    config = extract_config(otp_app, ecto_repos)

    GenServer.start_link(__MODULE__, config: config, enabled: enabled)
  end

  def init(config: _, enabled: false), do: :ignore

  def init(config: config, enabled: true) do
    log(config)

    :telemetry.attach_many(
      config.handler_id,
      config.events,
      &__MODULE__.handle_event/4,
      config
    )

    Process.flag(:trap_exit, true)
    {:ok, config}
  end

  def terminate(_reason, %{handler_id: handler_id}) do
    :telemetry.detach(handler_id)
  end

  # Telemetry handlers

  def handle_event(
        _event,
        %{total_time: total_time} = measurements,
        %{type: :ecto_sql_query, repo: repo} = metadata,
        config
      ) do
    end_time = System.system_time(:millisecond)

    duration_ms = total_time |> to_ms
    duration_s = duration_ms / 1000
    start_time = end_time - duration_ms

    query_time_ms = measurements[:query_time] |> to_ms
    queue_time_ms = measurements[:queue_time] |> to_ms
    decode_time_ms = measurements[:decode_time] |> to_ms

    %{hostname: hostname, port: port, database: database} = config.repo_configs[repo]

    query = (config.collect_sql? && metadata.query) || ""

    pid = inspect(self())
    id = {:ecto_sql_query, make_ref()}
    parent_id = Process.get(:nr_current_span) || :root

    with {datastore, table, operation} <- parse_ecto_metadata(metadata) do
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

      NewRelic.incr_attributes(
        databaseCallCount: 1,
        databaseDuration: duration_s,
        datastore_call_count: 1,
        datastore_duration_ms: duration_ms,
        "datastore.#{table}.call_count": 1,
        "datastore.#{table}.duration_ms": duration_ms
      )
    end
  end

  def handle_event(_event, _value, _metadata, _config) do
    :ignore
  end

  # Repo config extraction

  defp extract_config(otp_app, ecto_repos) do
    %{
      otp_app: otp_app,
      events: extract_events(otp_app, ecto_repos),
      repo_configs: extract_repo_configs(otp_app, ecto_repos),
      collect_sql?: NewRelic.Config.feature?(:sql_collection),
      handler_id: {:new_relic_ecto, otp_app}
    }
  end

  defp extract_events(otp_app, ecto_repos) do
    Enum.map(ecto_repos, fn repo ->
      ecto_telemetry_prefix(otp_app, repo) ++ [:query]
    end)
  end

  defp extract_repo_configs(otp_app, ecto_repos) do
    Enum.into(ecto_repos, %{}, fn repo ->
      {repo, extract_repo_config(otp_app, repo)}
    end)
  end

  defp extract_repo_config(otp_app, repo) do
    Application.get_env(otp_app, repo)
    |> Map.new()
    |> case do
      %{url: url} ->
        uri = URI.parse(url)

        %{
          hostname: uri.host,
          port: uri.port,
          database: uri.path |> String.trim_leading("/")
        }

      config ->
        config
    end
  end

  defp ecto_telemetry_prefix(otp_app, repo) do
    Application.get_env(otp_app, repo)
    |> Keyword.get_lazy(:telemetry_prefix, fn ->
      repo
      |> Module.split()
      |> Enum.map(&(&1 |> Macro.underscore() |> String.to_atom()))
    end)
  end

  # Ecto result parsing

  @postgrex_insert ~r/INSERT INTO "(?<table>\w+)"/
  @postgrex_create_table ~r/CREATE TABLE( IF NOT EXISTS)? "(?<table>\w+)"/
  defp parse_ecto_metadata(%{
         source: table,
         query: query,
         result: {:ok, %{__struct__: Postgrex.Result, command: operation}}
       }) do
    table =
      case {table, operation} do
        {nil, :insert} -> capture(@postgrex_insert, query, "table")
        {nil, :create_table} -> capture(@postgrex_create_table, query, "table")
        {nil, _} -> "other"
        {table, _} -> table
      end

    {"Postgres", table, operation}
  end

  @myxql_insert ~r/INSERT INTO `(?<table>\w+)`/
  @myxql_select ~r/FROM `(?<table>\w+)`/
  @myxql_create_table ~r/CREATE TABLE( IF NOT EXISTS)? `(?<table>\w+)`/
  defp parse_ecto_metadata(%{
         query: query,
         result: {:ok, %{__struct__: MyXQL.Result}}
       }) do
    {operation, table} =
      case query do
        "SELECT" <> _ -> {"select", capture(@myxql_select, query, "table")}
        "INSERT" <> _ -> {"insert", capture(@myxql_insert, query, "table")}
        "CREATE TABLE" <> _ -> {"create_table", capture(@myxql_create_table, query, "table")}
        "begin" -> {"other", :begin}
        "commit" -> {"other", :commit}
        _ -> {"other", "other"}
      end

    {"MySQL", table, operation}
  end

  defp parse_ecto_metadata(_) do
    raise "Unsupported ecto adapter"
  end

  # Helpers

  defp capture(regex, query, match) do
    Regex.named_captures(regex, query)[match]
  end

  defp log(%{repo_configs: repo_configs}) do
    for {repo, _config} <- repo_configs do
      NewRelic.log(:info, "Detected Ecto Repo #{inspect(repo)}")
    end
  end

  defp to_ms(nil), do: nil
  defp to_ms(ns), do: System.convert_time_unit(ns, :nanosecond, :millisecond)

  defp maybe_add(map, _, nil), do: map
  defp maybe_add(map, key, value), do: Map.put(map, key, value)
end
