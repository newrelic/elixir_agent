defmodule NewRelic.Util.HTTP do
  @moduledoc false

  def post(url, body, headers) when is_binary(body) do
    %{host: host} = URI.parse(url)
    headers = Enum.map(headers, fn {k, v} -> {'#{k}', '#{v}'} end)

    with {:ok, {{_, status_code, _}, _headers, body}} <-
           :httpc.request(
             :post,
             {'#{url}', headers, 'application/json', body},
             ssl_options(host),
             []
           ) do
      {:ok, %{status_code: status_code, body: to_string(body)}}
    end
  end

  def post(url, body, headers),
    do: post(url, Jason.encode!(body), headers)

  def ssl_options(host) do
    [
      ssl: [
        verify: :verify_peer,
        cacertfile: Application.app_dir(:new_relic_agent, "priv/cacert.pem"),
        verify_fun: {&:ssl_verify_hostname.verify_fun/3, [{:check_hostname, '#{host}'}]}
      ]
    ]
  end
end
