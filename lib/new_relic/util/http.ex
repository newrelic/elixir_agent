defmodule NewRelic.Util.Http do
  @moduledoc false

  def post(url, body, headers) when is_binary(body) do
    HTTPoison.post(url, body, headers, options())
  end

  def post(url, body, headers),
    do: post(url, Jason.encode!(body), headers)

  defp options() do
    case NewRelic.Config.proxy() do
      nil -> []
      proxy -> [proxy: proxy]
    end
  end
end
