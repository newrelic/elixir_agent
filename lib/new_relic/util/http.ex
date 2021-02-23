defmodule NewRelic.Util.HTTP do
  @moduledoc false

  @gzip {'content-encoding', 'gzip'}

  def post(url, body, headers) when is_binary(body) do
    headers = [@gzip | Enum.map(headers, fn {k, v} -> {'#{k}', '#{v}'} end)]
    request = {'#{url}', headers, 'application/json', :zlib.gzip(body)}

    with {:ok, {{_, status_code, _}, _headers, body}} <-
           :httpc.request(:post, request, http_options(), []) do
      {:ok, %{status_code: status_code, body: to_string(body)}}
    end
  end

  def post(url, body, headers) do
    case Jason.encode(body) do
      {:ok, body} ->
        post(url, body, headers)

      {:error, message} ->
        NewRelic.log(:debug, "Unable to JSON encode: #{inspect(body)}")
        {:error, message}
    end
  end

  @doc """
  Certs are pulled from Mozilla exactly as Hex does:
  https://github.com/hexpm/hex/blob/master/README.md#bundled-ca-certs

  SSL configured according to EEF Security guide:
  https://erlef.github.io/security-wg/secure_coding_and_deployment_hardening/ssl
  """
  def http_options() do
    [
      connect_timeout: 1000,
      ssl: [
        verify: :verify_peer,
        cacertfile: Application.app_dir(:new_relic_agent, "priv/cacert.pem"),
        customize_hostname_check: [
          match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
        ]
      ]
    ]
  end
end
