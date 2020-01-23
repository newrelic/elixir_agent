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
      |> parse_collector_response(params)

  defp issue_call(params, payload),
    do:
      params
      |> collector_method_url
      |> NewRelic.Util.HTTP.post(payload, collector_headers())
      |> parse_http_response(params)

  defp retry_call({:ok, response}, _params, _payload), do: {:ok, response}
  defp retry_call({:error, _response}, params, payload), do: issue_call(params, payload)

  defp collector_method_url(params) do
    params = Map.merge(default_collector_params(), params)

    %URI{
      host:
        Application.get_env(:new_relic_agent, :collector_instance_host) ||
          Application.get_env(:new_relic_agent, :collector_host),
      path: "/agent_listener/invoke_raw_method",
      query: URI.encode_query(params),
      scheme: Application.get_env(:new_relic_agent, :scheme, "https"),
      port: Application.get_env(:new_relic_agent, :port, 443)
    }
    |> URI.to_string()
  end

  defp parse_http_response({:ok, %{status_code: 200, body: body}}, _params) do
    case Jason.decode(body) do
      {:ok, response} ->
        {:ok, response}

      {:error, jason_exception} ->
        NewRelic.log(:error, "Bad collector JSON: #{Exception.message(jason_exception)}")
        {:error, :bad_collector_response}
    end
  end

  defp parse_http_response({:ok, %{status_code: 202}}, _params) do
    {:ok, :accepted}
  end

  defp parse_http_response({:ok, %{status_code: status, body: body}}, params) do
    NewRelic.log(:error, "#{params[:method]}: (#{status}) #{body}")
    {:error, status}
  end

  defp parse_http_response({:error, reason}, params) do
    NewRelic.log(:error, "#{params[:method]}: #{inspect(reason)}")
    {:error, reason}
  end

  defp parse_collector_response(
         {:ok, %{"return_value" => %{"messages" => messages} = return_value}},
         _params
       ) do
    Enum.each(messages, &NewRelic.log(:info, &1["message"]))
    {:ok, return_value}
  end

  defp parse_collector_response({:ok, %{"return_value" => return_value}}, _params) do
    {:ok, return_value}
  end

  defp parse_collector_response({:ok, %{"exception" => exception}}, %{method: method}) do
    exception_type = respond_to_exception(exception, method)
    {:error, exception_type}
  end

  defp parse_collector_response({:ok, :accepted}, _params) do
    {:ok, :accepted}
  end

  defp parse_collector_response({:error, reason}, _params) do
    {:error, reason}
  end

  defp parse_collector_response(response, method) do
    NewRelic.log(:error, "#{method}: (Unexpected collector response) #{inspect(response)}")
    {:error, :unexpected_collector_response}
  end

  defp respond_to_exception(%{"error_type" => error_type} = exception, method)
       when error_type in [
              "NewRelic::Agent::ForceDisconnectException",
              "NewRelic::Agent::LicenseException"
            ] do
    NewRelic.log(:error, "#{method}: (#{error_type}) #{exception["message"]}")
    NewRelic.log(:error, "Disabling agent harvest")

    Application.put_env(:new_relic_agent, :harvest_enabled, false)

    :license_exception
  end

  defp respond_to_exception(%{"error_type" => error_type} = exception, method)
       when error_type in [
              "NewRelic::Agent::ForceRestartException"
            ] do
    NewRelic.log(:error, "#{method}: (#{error_type}) #{exception["message"]}")
    NewRelic.log(:error, "Reconnecting agent")

    Collector.AgentRun.reconnect()

    :force_restart_exception
  end

  defp respond_to_exception(%{"error_type" => error_type} = exception, method) do
    NewRelic.log(:error, "#{method}: (#{error_type}) #{exception["message"]}")

    :collector_exception
  end

  defp respond_to_exception(exception, method) do
    NewRelic.log(:error, "#{method}: Unexpected collector exception: #{inspect(exception)}")

    :unexpected_exception
  end

  defp collector_headers do
    ["user-agent": "NewRelic-ElixirAgent/#{NewRelic.Config.agent_version()}"] ++
      Collector.AgentRun.lookup(:request_headers, [])
  end

  defp default_collector_params,
    do: %{
      license_key: NewRelic.Config.license_key(),
      marshal_format: "json",
      protocol_version: @protocol_version
    }
end
