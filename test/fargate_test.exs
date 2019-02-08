defmodule FargateTest do
  use ExUnit.Case
  alias NewRelic.Util.Vendor.Fargate

  @test_metadata_path "test/fargate-metadata.json"

  describe "fargate_hash" do
    test "when a path to the metadata file is provided" do
      util = Fargate.fargate_hash(%{}, @test_metadata_path)

      assert get_in(util, [:vendors, :aws, "Cluster"]) == "default"

      assert get_in(util, [:vendors, :aws, "ImageID"]) ==
               "sha256:c24f66af34b4d76558f7743109e2476b6325fcf6cc167c6e1e07cd121a22b341"

      assert get_in(util, [:vendors, :aws, "ImageName"]) == "httpd:2.4"

      assert get_in(util, [:vendors, :aws, "ContainerID"]) ==
               "98e44444008169587b826b4cd76c6732e5899747e753af1e19a35db64f9e9c32"

      assert get_in(util, [:vendors, :aws, "ContainerName"]) == "metadata"
    end

    test "when file does not exist" do
      initial_util = %{key: "value"}

      util = Fargate.fargate_hash(initial_util, "non-exisiting-path")

      assert util == initial_util
    end

    test "when ECS_CONTAINER_METADATA_FILE is set to an existing file path" do
      System.put_env("ECS_CONTAINER_METADATA_FILE", @test_metadata_path)

      util = Fargate.fargate_hash(%{})

      assert get_in(util, [:vendors, :aws, "Cluster"]) == "default"

      assert get_in(util, [:vendors, :aws, "ImageID"]) ==
               "sha256:c24f66af34b4d76558f7743109e2476b6325fcf6cc167c6e1e07cd121a22b341"

      assert get_in(util, [:vendors, :aws, "ImageName"]) == "httpd:2.4"

      assert get_in(util, [:vendors, :aws, "ContainerID"]) ==
               "98e44444008169587b826b4cd76c6732e5899747e753af1e19a35db64f9e9c32"

      assert get_in(util, [:vendors, :aws, "ContainerName"]) == "metadata"
    end

    test "when ECS_CONTAINER_METADATA_FILE is set to a non existing file path" do
      System.put_env("ECS_CONTAINER_METADATA_FILE", "non-exisiting-path")

      util = Fargate.fargate_hash(%{})

      assert util == %{}
    end
  end
end
