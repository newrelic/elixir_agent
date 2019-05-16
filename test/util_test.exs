defmodule UtilTest do
  use ExUnit.Case

  test "respects max attr size" do
    events = [%{giant: String.duplicate("A", 5_000), gianter: String.duplicate("A", 10_000)}]
    [%{giant: giant, gianter: gianter}] = NewRelic.Util.Event.process(events)
    assert String.length(giant) == 4095
    assert String.length(gianter) == 4095
  end

  test "Processes various attribute types" do
    assert %{key: "blah"} == NewRelic.Util.Event.process_event(%{key: "blah"})
    assert %{key: 1.2} == NewRelic.Util.Event.process_event(%{key: 1.2})
    assert %{key: [1, 2, 3]} == NewRelic.Util.Event.process_event(%{key: [1, 2, 3]})

    # Don't fail if a bitstring winds up there
    assert NewRelic.Util.Event.process_event(%{key: <<1::3>>})

    # Don't fail if a pid winds up in there
    assert NewRelic.Util.Event.process_event(%{key: self()})

    # Don't inspect the nodename, we don't want the atom char in the attribute
    json = NewRelic.Util.Event.process_event(%{key: Node.self()}) |> Jason.encode!()
    refute json =~ ":node"
  end

  test "flatten deeply nested map attributes" do
    flattened =
      NewRelic.Util.deep_flatten(not_nested: "value", nested: %{foo: %{bar: %{baz: "qux"}}})

    assert {"nested.foo.bar.baz", "qux"} in flattened
    assert {:not_nested, "value"} in flattened
  end

  test "Truncates unicode strings correctly" do
    %{key: truncated} =
      NewRelic.Util.Event.process_event(%{key: String.duplicate("a", 4094) <> "é"})

    assert byte_size(truncated) == 4094
  end

  defmodule FakeAwsPlug do
    import Plug.Conn

    def init(options), do: options

    def call(conn, _opts) do
      send_resp(conn, 200, """
      {
        "instanceId": "test.id",
        "instanceType": "test.type",
        "availabilityZone": "us-west-2b"
      }
      """)
    end
  end

  test "minimal utilization check" do
    assert %{metadata_version: 3} = NewRelic.Util.utilization()
  end

  test "AWS utilization fast timeout" do
    assert %{} ==
             NewRelic.Util.Vendor.maybe_add_cloud_vendors(%{},
               aws_url: "http://httpbin.org/delay/10"
             )
  end

  test "AWS utilization info" do
    {:ok, _} = Plug.Cowboy.http(FakeAwsPlug, [], port: 8883)

    util = NewRelic.Util.Vendor.maybe_add_cloud_vendors(%{}, aws_url: "http://localhost:8883")
    assert get_in(util, [:vendors, :aws, "instanceId"]) == "test.id"
  end

  test "hostname detection" do
    System.put_env("DYNO", "foobar")
    assert NewRelic.Util.hostname() == "foobar"

    System.put_env("DYNO", "run.100")
    assert NewRelic.Util.hostname() == "run.*"

    System.delete_env("DYNO")
    hostname = NewRelic.Util.hostname()
    assert is_binary(hostname)
  end

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
      assert {:ok, _} = NewRelic.Util.HTTP.post("https://sha512.badssl.com/", "", [])
    end
  end
end
