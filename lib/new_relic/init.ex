defmodule NewRelic.Init do
  @moduledoc false

  alias NewRelic.Harvest.Collector
  alias NewRelic.Harvest.TelemetrySdk

  def run() do
    verify_erlang_otp_version()
    init_config()
    init_features()
  end

  @erlang_version_requirement ">= 21.2.0"
  def verify_erlang_otp_version() do
    cond do
      Code.ensure_loaded?(:persistent_term) -> :ok
      Version.match?(System.otp_release() <> ".0.0", @erlang_version_requirement) -> :ok
      true -> raise "Erlang/OTP 21.2 required to run the New Relic agent"
    end
  end

  def init_config() do
    host = determine_config(:host)
    license_key = determine_config(:license_key)
    region_prefix = determine_region(license_key)

    collector_host = Collector.Protocol.determine_host(host, region_prefix)
    telemetry_hosts = TelemetrySdk.Config.determine_hosts(host, region_prefix)

    NewRelic.Config.put(%{
      log: determine_config(:log),
      host: host,
      display_host: determine_config(:display_host),
      port: determine_config(:port, 443) |> parse_port,
      scheme: determine_config(:scheme, "https"),
      app_name: determine_config(:app_name) |> parse_app_names,
      license_key: license_key,
      harvest_enabled: determine_config(:harvest_enabled, true) |> parse_bool,
      collector_host: collector_host,
      region_prefix: region_prefix,
      automatic_attributes: determine_automatic_attributes(),
      labels: determine_config(:labels) |> parse_labels(),
      ignore_paths: determine_config(:ignore_paths, []),
      telemetry_hosts: telemetry_hosts,
      trace_mode: determine_trace_mode()
    })
  end

  @region_matcher ~r/^(?<prefix>.+?)x/
  def determine_region(nil), do: nil

  def determine_region(license_key) do
    case Regex.named_captures(@region_matcher, license_key) do
      %{"prefix" => prefix} -> String.trim_trailing(prefix, "x")
      _ -> nil
    end
  end

  def init_features() do
    NewRelic.Config.put(:features, %{
      error_collector:
        determine_feature(
          "NEW_RELIC_ERROR_COLLECTOR_ENABLED",
          :error_collector_enabled
        ),
      query_collection:
        determine_feature(
          "NEW_RELIC_SQL_COLLECTION_ENABLED",
          :sql_collection_enabled,
          false
        ) ||
          determine_feature(
            "NEW_RELIC_DB_QUERY_COLLECTION_ENABLED",
            :db_query_collection_enabled,
            false
          ) ||
          determine_feature(
            "NEW_RELIC_QUERY_COLLECTION_ENABLED",
            :query_collection_enabled
          ),
      distributed_tracing:
        determine_feature(
          "NEW_RELIC_DISTRIBUTED_TRACING_ENABLED",
          :distributed_tracing_enabled
        ),
      ecto_instrumentation:
        determine_feature(
          "NEW_RELIC_ECTO_INSTRUMENTATION_ENABLED",
          :ecto_instrumentation_enabled
        ),
      redix_instrumentation:
        determine_feature(
          "NEW_RELIC_REDIX_INSTRUMENTATION_ENABLED",
          :redix_instrumentation_enabled
        ),
      absinthe_instrumentation:
        determine_feature(
          "NEW_RELIC_ABSINTHE_INSTRUMENTATION_ENABLED",
          :absinthe_instrumentation_enabled
        ),
      plug_instrumentation:
        determine_feature(
          "NEW_RELIC_PLUG_INSTRUMENTATION_ENABLED",
          :plug_instrumentation_enabled
        ),
      phoenix_instrumentation:
        determine_feature(
          "NEW_RELIC_PHOENIX_INSTRUMENTATION_ENABLED",
          :phoenix_instrumentation_enabled
        ),
      phoenix_live_view_instrumentation:
        determine_feature(
          "NEW_RELIC_PHOENIX_LIVE_VIEW_INSTRUMENTATION_ENABLED",
          :phoenix_live_view_instrumentation_enabled
        ),
      oban_instrumentation:
        determine_feature(
          "NEW_RELIC_OBAN_INSTRUMENTATION_ENABLED",
          :oban_instrumentation_enabled
        ),
      finch_instrumentation:
        determine_feature(
          "NEW_RELIC_FINCH_INSTRUMENTATION_ENABLED",
          :finch_instrumentation_enabled
        ),
      function_argument_collection:
        determine_feature(
          "NEW_RELIC_FUNCTION_ARGUMENT_COLLECTION_ENABLED",
          :function_argument_collection_enabled
        ),
      stacktrace_argument_collection:
        determine_feature(
          "NEW_RELIC_STACKTRACE_ARGUMENT_COLLECTION_ENABLED",
          :stacktrace_argument_collection_enabled
        ),
      request_queuing_metrics:
        determine_feature(
          "NEW_RELIC_REQUEST_QUEUING_METRICS_ENABLED",
          :request_queuing_metrics_enabled
        ),
      extended_attributes:
        determine_feature(
          "NEW_RELIC_EXTENDED_ATTRIBUTES_ENABLED",
          :extended_attributes_enabled
        )
    })
  end

  def determine_config(key, default \\ nil) when is_atom(key) do
    env = key |> to_string() |> String.upcase()

    System.get_env("NEW_RELIC_#{env}") ||
      Application.get_env(:new_relic_agent, key, default)
  end

  defp determine_feature(env, config, default \\ true) do
    case System.get_env(env) do
      "true" -> true
      "false" -> false
      _ -> Application.get_env(:new_relic_agent, config, default)
    end
  end

  defp determine_trace_mode() do
    (determine_config(:infinite_tracing_trace_observer_host) && :infinite) || :sampling
  end

  def determine_automatic_attributes() do
    Application.get_env(:new_relic_agent, :automatic_attributes, [])
    |> Map.new(fn
      {name, {:system, env_var}} -> {name, System.get_env(env_var)}
      {name, {m, f, a}} -> {name, apply(m, f, a)}
      {name, value} -> {name, value}
    end)
  end

  defp parse_bool(bool) when is_boolean(bool), do: bool
  defp parse_bool("true"), do: true
  defp parse_bool("false"), do: false

  def parse_port(port) when is_integer(port), do: port
  def parse_port(port) when is_binary(port), do: String.to_integer(port)

  def parse_app_names(nil), do: nil

  def parse_app_names(name_string) do
    name_string
    |> String.split(";")
    |> Enum.map(&String.trim/1)
  end

  def parse_labels(nil), do: []

  @label_splitter ~r/;|:/
  def parse_labels(label_string) do
    label_string
    |> String.split(@label_splitter, trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.chunk_every(2, 2, :discard)
  end
end
