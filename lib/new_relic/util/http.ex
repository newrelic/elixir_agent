defmodule NewRelic.Util.HTTP do
  @moduledoc false

  def post(url, body, headers) when is_binary(body) do
    url = ~c(#{url})
    headers = for({k, v} <- headers, do: {~c(#{k}), ~c(#{v})})

    {:ok, {{_, status_code, _}, _headers, body}} =
      :httpc.request(
        :post,
        {url, headers, 'application/json', body},
        NewRelic.Util.SSL.ssl_options(),
        []
      )

    {:ok, %{status_code: status_code, body: to_string(body)}}
  end

  def post(url, body, headers),
    do: post(url, Jason.encode!(body), headers)
end
