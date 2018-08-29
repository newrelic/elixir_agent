defmodule NewRelic.Harvest.Collector.Protocol do
  alias NewRelic.Harvest.Collector

  @moduledoc false

  @protocol_version 16

  def preconnect, do: call_remote(%{method: "preconnect"}, [])

  def connect(payload), do: call_remote(%{method: "connect"}, payload)

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

  defp call_remote(params, payload), do: call_remote(params, payload, NewRelic.Config.enabled?())

  defp call_remote(_params, _payload, false), do: {:error, :harvest_disabled}

  defp call_remote(params, payload, true),
    do:
      params
      |> issue_call(payload)
      |> retry_call(params, payload)
      |> parse_collector_response

  defp issue_call(params, payload),
    do:
      params
      |> collector_method_url
      |> NewRelic.Util.post(payload, collector_headers())
      |> parse_http_response

  defp retry_call({:ok, response}, _params, _payload), do: {:ok, response}
  defp retry_call({:error, _response}, params, payload), do: issue_call(params, payload)

  defp collector_method_url(params) do
    params = Map.merge(default_collector_params(), params)

    %URI{
      host:
        Application.get_env(:new_relic, :collector_instance_host) ||
          Application.get_env(:new_relic, :collector_host),
      path: "/agent_listener/invoke_raw_method",
      query: URI.encode_query(params),
      scheme: Application.get_env(:new_relic, :scheme, "https"),
      port: Application.get_env(:new_relic, :port, 443)
    }
    |> URI.to_string()
  end

  defp parse_http_response({:ok, {{_, 200, 'OK'}, _headers, body}}),
    do: {:ok, Jason.decode!(body)}

  defp parse_http_response({:ok, {{_, status, _}, _headers, body}}) do
    NewRelic.log(:error, "(#{status}) #{body}")
    {:error, status}
  end

  defp parse_http_response({:error, reason}) do
    NewRelic.log(:error, "#{inspect(reason)}")
    {:error, reason}
  end

  defp parse_collector_response({:error, code}), do: code
  defp parse_collector_response({:ok, %{"return_value" => return_value}}), do: return_value

  defp parse_collector_response({:ok, %{"exception" => exception_value}}),
    do: handle_exception(exception_value)

  defp handle_exception(%{"error_type" => error_type} = exception)
       when error_type in [
              "NewRelic::Agent::ForceDisconnectException",
              "NewRelic::Agent::LicenseException"
            ] do
    NewRelic.log(:error, exception["message"])
    NewRelic.log(:error, "Disabling agent harvest")
    Application.put_env(:new_relic, :harvest_enabled, false)
    {:error, :license_exception}
  end

  defp handle_exception(%{"error_type" => "NewRelic::Agent::ForceRestartException"} = exception) do
    NewRelic.log(:error, exception["message"])
    NewRelic.log(:error, "Reconnecting Agent")
    Collector.AgentRun.reconnect()
    {:error, :force_restart}
  end

  defp handle_exception(exception), do: exception

  defp collector_headers,
    do: [
      "content-encoding": "identity",
      "user-agent": "NewRelic-ElixirAgent/#{NewRelic.Config.agent_version()}"
    ]

  defp default_collector_params,
    do: %{
      license_key: NewRelic.Config.license_key(),
      marshal_format: "json",
      protocol_version: @protocol_version
    }
end
