defmodule NewRelic.Util.HTTP do
  @moduledoc false

  @gzip {~c"content-encoding", ~c"gzip"}

  def post(url, body, headers) when is_binary(body) do
    headers = [@gzip | Enum.map(headers, fn {k, v} -> {~c"#{k}", ~c"#{v}"} end)]
    request = {~c"#{url}", headers, ~c"application/json", :zlib.gzip(body)}

    with {:ok, {{_, status_code, _}, _headers, body}} <-
           :httpc.request(:post, request, http_options(), []) do
      {:ok, %{status_code: status_code, body: to_string(body)}}
    end
  end

  def post(url, body, headers) do
    body = NewRelic.JSON.encode!(body)
    post(url, body, headers)
  rescue
    error ->
      NewRelic.log(:debug, "Unable to JSON encode: #{inspect(body)}")
      {:error, Exception.message(error)}
  end

  def get(url, headers \\ [], opts \\ []) do
    headers = Enum.map(headers, fn {k, v} -> {~c"#{k}", ~c"#{v}"} end)
    request = {~c"#{url}", headers}

    with {:ok, {{_, status_code, _}, _, body}} <-
           :httpc.request(:get, request, http_options(opts), []) do
      {:ok, %{status_code: status_code, body: to_string(body)}}
    end
  end

  # Certs are from `CAStore`.
  # https://github.com/elixir-mint/castore

  # SSL configured according to EEF Security guide:
  # https://erlef.github.io/security-wg/secure_coding_and_deployment_hardening/ssl
  defp http_options(opts \\ []) do
    env_opts = Application.get_env(:new_relic_agent, :httpc_request_options, [])

    [
      connect_timeout: 1000,
      ssl: [
        verify: :verify_peer,
        cacertfile: CAStore.file_path(),
        customize_hostname_check: [
          match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
        ]
      ]
    ]
    |> Keyword.merge(opts)
    |> Keyword.merge(env_opts)
  end
end
