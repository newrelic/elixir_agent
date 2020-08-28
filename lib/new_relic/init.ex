defmodule NewRelic.Init do
  @moduledoc false

  def run() do
    verify_erlang_otp_version()
    init_collector_host()
  end

  @erlang_version_requirement ">= 21.0.0"
  def verify_erlang_otp_version() do
    if Version.match?(System.otp_release() <> ".0.0", @erlang_version_requirement) do
      :ok
    else
      raise "Erlang/OTP 21 required"
    end
  end

  def init_collector_host() do
    {collector_host, region_prefix} = determine_collector_host()

    Application.put_env(:new_relic_agent, :collector_host, collector_host)
    Application.put_env(:new_relic_agent, :region_prefix, region_prefix)
  end

  def determine_collector_host() do
    cond do
      manual_config_host = NewRelic.Config.host() ->
        {manual_config_host, nil}

      region_prefix = determine_region(NewRelic.Config.license_key()) ->
        {"collector.#{region_prefix}.nr-data.net", region_prefix}

      true ->
        {"collector.newrelic.com", nil}
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
