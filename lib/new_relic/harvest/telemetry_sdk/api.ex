defmodule NewRelic.Harvest.TelemetrySdk.API do
  def post(type, payload) do
    region_prefix = NewRelic.Config.region_prefix()

    NewRelic.Util.HTTP.post(
      url(type, region_prefix),
      payload,
      headers()
    )
  end

  defp headers() do
    [
      "X-License-Key": NewRelic.Config.license_key()
    ]
  end

  defp url(type, nil),
    do: "https://#{env()}#{type}-api.newrelic.com/#{type}/v1"

  defp url(type, region_prefix),
    do: "https://#{env()}#{type}-api.#{region_prefix}.newrelic.com/#{type}/v1"

  defp env() do
    case Application.get_env(:new_relic_agent, :melt_env) do
      nil -> nil
      env -> "#{env}-"
    end
  end
end
