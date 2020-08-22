defmodule NewRelic.Init do
  @moduledoc false

  def run() do
    verify_erlang_otp_version()
    init_collector_host()
    setup_logs_in_context()
  end

  def setup_logs_in_context() do
    # TODO: setup only if agent enabled & feature is on & Elixir 1.10+
    :logger.add_primary_filter(:nr_process_metadata, {&NewRelic.LogsInContext.primary_filter/2, []})
    Logger.configure_backend(:console, format: {NewRelic.LogsInContext, :format})
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
    Application.put_env(:new_relic_agent, :collector_host, determine_collector_host())
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
