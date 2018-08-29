defmodule NewRelic.Init do
  @moduledoc false

  def run() do
    init_collector_host()
  end

  def init_collector_host() do
    Application.put_env(:new_relic, :collector_host, determine_collector_host())
  end

  def determine_collector_host() do
    cond do
      manual_config_host = NewRelic.Config.host() ->
        manual_config_host

      region_prefix = determine_region(NewRelic.Config.license_key()) ->
        "collector.#{region_prefix}.nr-data.net"

      true ->
        "collector.newrelic.com"
    end
  end

  @region_matcher ~r/^(?<prefix>.+?)x/

  def determine_region(nil), do: false

  def determine_region(key) do
    case Regex.named_captures(@region_matcher, key) do
      %{"prefix" => prefix} -> String.trim_trailing(prefix, "x")
      _ -> false
    end
  end
end
