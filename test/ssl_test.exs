defmodule SSLTest do
  use ExUnit.Case

  describe "Verify SSL setup" do
    test "reject bad domains" do
      assert {:error,
              {:failed_connect,
               [
                 {:to_address, {'wrong.host.badssl.com', 443}},
                 {:inet, [:inet], {:tls_alert, _}}
               ]}} = NewRelic.Util.HTTP.post("https://wrong.host.badssl.com/", "", [])

      assert {:error,
              {:failed_connect,
               [
                 {:to_address, {'expired.badssl.com', 443}},
                 {:inet, [:inet], {:tls_alert, _}}
               ]}} = NewRelic.Util.HTTP.post("https://expired.badssl.com/", "", [])

      assert {:error,
              {:failed_connect,
               [
                 {:to_address, {'self-signed.badssl.com', 443}},
                 {:inet, [:inet], {:tls_alert, _}}
               ]}} = NewRelic.Util.HTTP.post("https://self-signed.badssl.com/", "", [])

      assert {:error,
              {:failed_connect,
               [
                 {:to_address, {'untrusted-root.badssl.com', 443}},
                 {:inet, [:inet], {:tls_alert, _}}
               ]}} = NewRelic.Util.HTTP.post("https://untrusted-root.badssl.com/", "", [])

      assert {:error,
              {:failed_connect,
               [
                 {:to_address, {'incomplete-chain.badssl.com', 443}},
                 {:inet, [:inet], {:tls_alert, _}}
               ]}} = NewRelic.Util.HTTP.post("https://incomplete-chain.badssl.com/", "", [])
    end

    test "allows good domains" do
      assert {:ok, _} = NewRelic.Util.HTTP.post("https://sha256.badssl.com/", "", [])
    end
  end
end
