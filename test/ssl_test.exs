defmodule SSLTest do
  use ExUnit.Case, async: true

  describe "Verify SSL setup" do
    test "reject bad domains" do
      assert {:error,
              {:failed_connect,
               [
                 {:to_address, {~c"wrong.host.badssl.com", 443}},
                 {:inet, [:inet], {:tls_alert, _}}
               ]}} = NewRelic.Util.HTTP.post("https://wrong.host.badssl.com/", "", [])

      assert {:error,
              {:failed_connect,
               [
                 {:to_address, {~c"expired.badssl.com", 443}},
                 {:inet, [:inet], {:tls_alert, _}}
               ]}} = NewRelic.Util.HTTP.post("https://expired.badssl.com/", "", [])

      assert {:error,
              {:failed_connect,
               [
                 {:to_address, {~c"self-signed.badssl.com", 443}},
                 {:inet, [:inet], {:tls_alert, _}}
               ]}} = NewRelic.Util.HTTP.post("https://self-signed.badssl.com/", "", [])

      assert {:error,
              {:failed_connect,
               [
                 {:to_address, {~c"untrusted-root.badssl.com", 443}},
                 {:inet, [:inet], {:tls_alert, _}}
               ]}} = NewRelic.Util.HTTP.post("https://untrusted-root.badssl.com/", "", [])

      assert {:error,
              {:failed_connect,
               [
                 {:to_address, {~c"incomplete-chain.badssl.com", 443}},
                 {:inet, [:inet], {:tls_alert, _}}
               ]}} = NewRelic.Util.HTTP.post("https://incomplete-chain.badssl.com/", "", [])
    end

    test "allows good domains" do
      assert {:ok, _} = NewRelic.Util.HTTP.post("https://sha256.badssl.com/", "", [])
    end
  end
end
