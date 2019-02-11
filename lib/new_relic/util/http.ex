defmodule NewRelic.Util.HTTP do
  @moduledoc false

  @gzip {'content-encoding', 'gzip'}

  def post(url, body, headers) when is_binary(body) do
    headers = [@gzip | Enum.map(headers, fn {k, v} -> {'#{k}', '#{v}'} end)]
    request = {'#{url}', headers, 'application/json', :zlib.gzip(body)}
    %{host: host} = URI.parse(url)

    with {:ok, {{_, status_code, _}, _headers, body}} <-
           :httpc.request(:post, request, ssl_options(host), []) do
      {:ok, %{status_code: status_code, body: to_string(body)}}
    end
  end

  def post(url, body, headers),
    do: post(url, Jason.encode!(body), headers)

  @doc """
  Certs are pulled from Mozilla exactly as Hex does:
  https://github.com/hexpm/hex/blob/master/README.md#bundled-ca-certs
  """
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
