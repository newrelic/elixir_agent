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
    json = NewRelic.Util.Event.process_event(%{key: Node.self()}) |> NewRelic.JSON.encode!()
    refute json =~ ":node"
  end

  test "flatten deeply nested map attributes" do
    flattened =
      NewRelic.Util.deep_flatten(
        not_nested: "value",
        nested: %{foo: %{bar: %{baz: "qux"}}},
        nested_list: [%{one: %{two: "three"}}, %{four: "five"}, %{}, "string", ["nested string"]],
        super_long_list: Enum.map(0..99, & &1),
        big_map: String.graphemes("abcdefghijklmnopqrstuvwxyz") |> Enum.into(%{}, &{&1, &1})
      )

    assert {"nested.foo.bar.baz", "qux"} in flattened
    assert {:not_nested, "value"} in flattened
    assert {"nested_list.0.one.two", "three"} in flattened
    assert {"nested_list.1.four", "five"} in flattened
    assert {"nested_list.3", "string"} in flattened
    assert {"nested_list.4.0", "nested string"} in flattened
    assert {"super_long_list.0", 0} in flattened
    assert {"super_long_list.1", 1} in flattened
    assert {"super_long_list.9", 9} in flattened
    refute {"super_long_list.10", 10} in flattened
    assert {"super_long_list.length", 100} in flattened
    assert {"big_map.a", "a"} in flattened
    assert {"big_map.j", "j"} in flattened
    refute {"big_map.k", "k"} in flattened
    assert {"big_map.size", 26} in flattened
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
    assert %{metadata_version: 5} = util = NewRelic.Util.utilization()

    assert util[:ip_address] |> is_list
    assert util[:full_hostname] |> is_binary
  end

  test "AWS utilization fast timeout" do
    assert %{} ==
             NewRelic.Util.Vendor.maybe_add_vendors(%{},
               aws_url: "http://httpbin.org/delay/10"
             )
  end

  test "AWS utilization info" do
    {:ok, _} = Plug.Cowboy.http(FakeAwsPlug, [], port: 8883)

    util = NewRelic.Util.Vendor.maybe_add_vendors(%{}, aws_url: "http://localhost:8883")
    assert get_in(util, [:vendors, :aws, "instanceId"]) == "test.id"
  end

  test "Kubernetes utilization info" do
    System.put_env("KUBERNETES_SERVICE_HOST", "k8s-host")

    util = NewRelic.Util.utilization()
    assert get_in(util, [:vendors, :kubernetes, :kubernetes_service_host]) == "k8s-host"

    System.delete_env("KUBERNETES_SERVICE_HOST")
  end

  test "New Relic metadata detection" do
    System.put_env("NEW_RELIC_METADATA_TEST", "value")

    assert NewRelic.Util.metadata() == %{"NEW_RELIC_METADATA_TEST" => "value"}

    System.delete_env("NEW_RELIC_METADATA_TEST")
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

  test "docker cgroup file container ID detection" do
    # docker-0.9.1
    assert_docker_container_id(
      """
      9:cpu,cpuacct:/kubepods/besteffort/pod88ba95f5-37f2-4a9d-a9f4-585b20f006cc/1dfca6ba5656
      1:cpu,cpuacct:/kubepods/besteffort/pod88ba95f5-37f2-4a9d-a9f4-585b20f006cc/d77a1dfca6ba5656b1e1c77fa67cedad49c583cdba6ab95d111935c31005ffe7
      """,
      "d77a1dfca6ba5656b1e1c77fa67cedad49c583cdba6ab95d111935c31005ffe7"
    )

    # docker-1.3
    assert_docker_container_id(
      """
      3:cpuacct:/docker/47cbd16b77c50cbf71401c069cd2189f0e659af17d5a2daca3bddf59d8a870b2
      2:cpu:/docker/47cbd16b77c50cbf71401c069cd2189f0e659af17d5a2daca3bddf59d8a870b2
      1:cpuset:/
      """,
      "47cbd16b77c50cbf71401c069cd2189f0e659af17d5a2daca3bddf59d8a870b2"
    )

    # docker-custom-prefix
    assert_docker_container_id(
      """
      4:cpu:/custom-foobar/e6aaf072b17c345d900987ce04e37031d198b02314f8636df2c0edf6538c08c7
      """,
      "e6aaf072b17c345d900987ce04e37031d198b02314f8636df2c0edf6538c08c7"
    )

    # docker-gcp
    assert_docker_container_id(
      """
      2:cpu:/f96c541a87e1376f25461f1386cb60208cea35750eac1e24e11566f078715920
      """,
      "f96c541a87e1376f25461f1386cb60208cea35750eac1e24e11566f078715920"
    )

    # ubuntu-14.04-lxc-container
    assert_docker_container_id(
      """
      4:cpu:/lxc/p1
      """,
      :none
    )

    # ubuntu-14.04-no-container
    assert_docker_container_id(
      """
      4:cpu:/user/1000.user/2.session
      """,
      :none
    )

    # invalid-characters
    assert_docker_container_id(
      """
      3:cpuacct:/docker/WRONGINCORRECTINVALIDCHARSERRONEOUSBADPHONYBROKEN2TERRIBLENOPE55
      2:cpu:/docker/WRONGINCORRECTINVALIDCHARSERRONEOUSBADPHONYBROKEN2TERRIBLENOPE55
      """,
      :none
    )

    # invalid-length
    assert_docker_container_id(
      """
      3:cpuacct:/docker/47cbd16b77c5
      2:cpu:/docker/47cbd16b77c5
      """,
      :none
    )

    # no_cpu_subsystem
    assert_docker_container_id(
      """
      6:memory:/docker/f37a7e4d17017e7bf774656b19ca4360c6cdc4951c86700a464101d0d9ce97ee
      5:cpuacct:/docker/f37a7e4d17017e7bf774656b19ca4360c6cdc4951c86700a464101d0d9ce97ee
      4:cpu:/
      """,
      :none
    )

    # heroku
    assert_docker_container_id(
      """
      1:hugetlb,perf_event,blkio,freezer,devices,memory,cpuacct,cpu,cpuset:/lxc/b6d196c1-50f2-4949-abdb-5d4909864487
      """,
      :none
    )

    # empty
    assert_docker_container_id(
      "",
      :none
    )
  end

  @test_cgroup_filename "/tmp/nr_agent_test_cgroup"
  def assert_docker_container_id(cgroup_file, id) do
    File.write!(@test_cgroup_filename, cgroup_file)

    expected =
      case id do
        :none -> %{}
        id -> %{docker: %{"id" => id}}
      end

    assert expected ==
             NewRelic.Util.Vendor.maybe_add_docker(%{}, cgroup_filename: @test_cgroup_filename)

    File.rm!(@test_cgroup_filename)
  end

  test "uuid4 generation" do
    uuid4 = NewRelic.Util.uuid4()

    [u0, u1, u2, u3, u4] = String.split(uuid4, "-")

    assert String.length(u0) == 8
    assert String.length(u1) == 4
    assert String.length(u2) == 4
    assert String.length(u3) == 4
    assert String.length(u4) == 12
  end
end
