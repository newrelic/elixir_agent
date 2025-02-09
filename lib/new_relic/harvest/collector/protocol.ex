defmodule NewRelic.Harvest.Collector.Protocol do
  alias NewRelic.Harvest.Collector

  @moduledoc false

  @protocol_version 17

  def preconnect,
    do: call_remote(%{method: "preconnect"}, [])

  def connect(payload),
    do: call_remote(%{method: "connect"}, payload)

  def transaction_event([agent_run_id, _sampling, _events] = payload),
    do: call_remote(%{method: "analytic_event_data", run_id: agent_run_id}, payload)

  def error_event([agent_run_id, _sampling, _events] = payload),
    do: call_remote(%{method: "error_event_data", run_id: agent_run_id}, payload)

  def span_event([agent_run_id, _sampling, _spans] = payload),
    do: call_remote(%{method: "span_event_data", run_id: agent_run_id}, payload)

  def custom_event([agent_run_id, _sampling, _events] = payload),
    do: call_remote(%{method: "custom_event_data", run_id: agent_run_id}, payload)

  def metric_data([agent_run_id, _ts_start, _ts_end, _data_array] = payload),
    do: call_remote(%{method: "metric_data", run_id: agent_run_id}, payload)

  def error([agent_run_id, _errors] = payload),
    do: call_remote(%{method: "error_data", run_id: agent_run_id}, payload)

  def transaction_trace([agent_run_id, _traces] = payload),
    do: call_remote(%{method: "transaction_sample_data", run_id: agent_run_id}, payload)

  defp call_remote(params, payload) do
    call_remote(params, payload, NewRelic.Config.enabled?())
  end

  defp call_remote(%{run_id: nil}, _payload, _enabled) do
    {:error, :not_connected}
  end

  defp call_remote(_params, _payload, false) do
    {:error, :harvest_disabled}
  end

  defp call_remote(params, payload, true),
    do:
      params
      |> issue_call(payload)
      |> retry_call(params, payload)
      |> handle_collector_response(params)

  defp issue_call(params, payload),
    do:
      params
      |> collector_method_url
      |> post(payload)
      |> parse_http_response(params)

  defp post(url, payload) do
    if Application.get_env(:new_relic_agent, :bypass_collector, false) do
      {:error, :bypass_collector}
    else
      NewRelic.Util.HTTP.post(url, payload, collector_headers())
    end
  end

  defp retry_call({:ok, response}, _params, _payload), do: {:ok, response}

  @retryable [408, 429, 500, 503]
  defp retry_call({:error, status}, params, payload) when status in @retryable,
    do: issue_call(params, payload)

  defp retry_call({:error, error}, _params, _payload), do: {:error, error}

  defp collector_method_url(params) do
    params = Map.merge(default_collector_params(), params)

    host =
      Application.get_env(:new_relic_agent, :collector_instance_host) ||
        NewRelic.Config.get(:collector_host)

    %URI{
      host: host,
      path: "/agent_listener/invoke_raw_method",
      query: URI.encode_query(params),
      scheme: NewRelic.Config.get(:scheme),
      port: NewRelic.Config.get(:port)
    }
    |> URI.to_string()
  end

  defp parse_http_response({:ok, %{status_code: 200, body: body}}, _params) do
    {:ok, NewRelic.JSON.decode!(body)}
  rescue
    error ->
      NewRelic.log(:error, "Bad collector JSON: #{Exception.message(error)}")
      {:error, :bad_collector_response}
  end

  defp parse_http_response({:ok, %{status_code: 202}}, _params) do
    {:ok, :accepted}
  end

  @force_restart [401, 409]
  defp parse_http_response({:ok, %{status_code: status_code, body: body}}, params)
       when status_code in @force_restart do
    NewRelic.report_metric({:supportability, :collector}, status: status_code)
    log_error(status_code, :force_restart, params, body)
    {:error, :force_restart}
  end

  @force_disconnect [410]
  defp parse_http_response({:ok, %{status_code: status_code, body: body}}, params)
       when status_code in @force_disconnect do
    NewRelic.report_metric({:supportability, :collector}, status: status_code)
    log_error(status_code, :force_disconnect, params, body)
    {:error, :force_disconnect}
  end

  defp parse_http_response({:ok, %{status_code: status, body: body}}, params) do
    NewRelic.report_metric({:supportability, :collector}, status: status)
    log_error(status, :unexpected_response, params, body)
    {:error, status}
  end

  defp parse_http_response({:error, :bypass_collector}, _params) do
    {:error, :bypass_collector}
  end

  defp parse_http_response({:error, reason}, params) do
    log_error(:failed_request, reason, params)
    {:error, reason}
  end

  defp handle_collector_response(
         {:ok, %{"return_value" => %{"messages" => messages} = return_value}},
         _params
       ) do
    Enum.each(messages, &NewRelic.log(:info, &1["message"]))
    {:ok, return_value}
  end

  defp handle_collector_response({:ok, %{"return_value" => return_value}}, _params) do
    {:ok, return_value}
  end

  defp handle_collector_response({:ok, :accepted}, _params) do
    {:ok, :accepted}
  end

  defp handle_collector_response({:error, :force_disconnect}, _params) do
    NewRelic.log(:error, "Disabling agent harvest")
    Application.put_env(:new_relic_agent, :harvest_enabled, false)
    NewRelic.Init.init_config()
    {:error, :force_disconnect}
  end

  defp handle_collector_response({:error, :force_restart}, _params) do
    NewRelic.log(:error, "Reconnecting agent")
    Collector.AgentRun.reconnect()
    {:error, :force_restart}
  end

  defp handle_collector_response({:error, reason}, _params) do
    {:error, reason}
  end

  defp log_error(error, reason, params) do
    NewRelic.log(:error, "#{params[:method]}: (#{error}) #{inspect(reason)}")
  end

  defp log_error(error, reason, params, "") do
    NewRelic.log(:error, "#{params[:method]}: (#{error}) #{inspect(reason)}")
  end

  defp log_error(status, error, params, body) do
    case NewRelic.JSON.decode(body) do
      {:ok, %{"exception" => exception}} ->
        NewRelic.log(
          :error,
          "#{params[:method]}: (#{status}) #{error} - " <>
            "#{exception["error_type"]} - #{exception["message"]}"
        )

      _ ->
        NewRelic.log(:error, "#{params[:method]}: (#{status}) #{error} - #{body}")
    end
  end

  defp collector_headers do
    ["user-agent": "NewRelic-ElixirAgent/#{NewRelic.Config.agent_version()}"] ++
      (Collector.AgentRun.request_headers() || [])
  end

  def determine_host(manual_config_host, region_prefix) do
    cond do
      manual_config_host -> manual_config_host
      region_prefix -> "collector.#{region_prefix}.nr-data.net"
      true -> "collector.newrelic.com"
    end
  end

  defp default_collector_params,
    do: %{
      license_key: NewRelic.Config.license_key(),
      marshal_format: "json",
      protocol_version: @protocol_version
    }
end
