defmodule NewRelic.Util.SSL do
  @moduledoc false

  # See: https://github.com/hexpm/hex/blob/master/lib/hex/http/certs.ex
  @cacertfile Path.expand("cacert.pem")
  @external_resource @cacertfile
  @cacerts File.read!(@cacertfile)
           |> :public_key.pem_decode()
           |> Enum.map(fn {:Certificate, der, _} -> der end)

  def ssl_options() do
    [
      ssl: [
        verify: :verify_peer,
        cacerts: @cacerts,
        # See: https://github.com/erlang/otp/blob/8ca061c3006ad69c2a8d1c835d0d678438966dfc/lib/ssl/src/ssl.erl#L1121
        verify_fun: fn [{:bad_cert, _}] -> false end
      ]
    ]
  end
end
