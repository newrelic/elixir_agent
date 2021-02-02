defmodule NewRelic.Harvest.TelemetrySdk.API do
  @moduledoc false

  def log(logs) do
    url = url(:log)
    payload = {:logs, logs, generate_request_id()}

    request(url, payload)
    |> maybe_retry(url, payload)
  end

  def span(spans) do
    url = url(:trace)
    payload = {:spans, spans, generate_request_id()}

    request(url, payload)
    |> maybe_retry(url, payload)
  end

  def request(url, payload) do
    post(url, payload)
  end

  @success 200..299
  @drop [400, 401, 403, 405, 409, 410, 411]
  def maybe_retry({:ok, %{status_code: status_code}} = result, _, _)
      when status_code in @success
      when status_code in @drop do
    result
  end

  # 413 split

  # 408, 500+
  def maybe_retry(_result, url, payload) do
    post(url, payload)
  end

  def post(url, {_, payload, request_id}) do
    NewRelic.Util.HTTP.post(url, payload, headers(request_id))
  end

  defp url(type) do
    NewRelic.Config.get(:telemetry_hosts)[type]
  end

  defp headers(request_id) do
    [
      "X-Request-Id": request_id,
      "X-License-Key": NewRelic.Config.license_key(),
      "User-Agent": user_agent()
    ]
  end

  defp user_agent() do
    "NewRelic-Elixir-TelemetrySDK/0.1.0 " <>
      "NewRelic-Elixir-Agent/#{NewRelic.Config.agent_version()}"
  end

  defp generate_request_id() do
    NewRelic.Util.uuid4()
  end
end
