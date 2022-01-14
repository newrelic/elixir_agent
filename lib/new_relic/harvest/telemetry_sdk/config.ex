defmodule NewRelic.Harvest.TelemetrySdk.Config do
  @moduledoc false

  @default %{
    logs_harvest_cycle: 5_000,
    spans_harvest_cycle: 5_000,
    dimensional_metrics_harvest_cycle: 5_000
  }
  def lookup(key) do
    Application.get_env(:new_relic_agent, key, @default[key])
  end

  @region_matcher ~r/^(?<region>\D+)/
  @env_matcher ~r/^(?<env>.+)-collector/
  def determine_hosts(host, region) do
    env = host && Regex.named_captures(@env_matcher, host)["env"]
    env = env && env <> "-"
    region = region && Regex.named_captures(@region_matcher, region)["region"] <> "."

    %{
      log: "https://#{env}log-api.#{region}newrelic.com/log/v1",
      trace: trace_domain(env, region),
      metric: metric_domain(env, region)
    }
  end

  defp trace_domain(env, region) do
    infinite_tracing_host = NewRelic.Init.determine_config(:infinite_tracing_trace_observer_host)
    trace_domain(env, region, infinite_tracing_host)
  end

  defp trace_domain(env, region, nil) do
    "https://#{env}trace-api.#{region}newrelic.com/trace/v1"
  end

  defp trace_domain(_env, _region, infinite_tracing_host) do
    "https://#{infinite_tracing_host}/trace/v1"
  end

  defp metric_domain(env, region) do
    "https://#{env}metric-api.#{region}newrelic.com/metric/v1"
  end
end
