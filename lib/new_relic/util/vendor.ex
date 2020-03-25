defmodule NewRelic.Util.Vendor do
  @moduledoc false

  @cgroup_file "/proc/self/cgroup"

  def maybe_add_vendors(util, options \\ []) do
    %{}
    |> maybe_add_aws(options)
    |> maybe_add_kubernetes()
    |> maybe_add_docker_container_id(@cgroup_file)
    |> case do
      vendors when map_size(vendors) == 0 -> util
      vendors -> Map.put(util, :vendors, vendors)
    end
  end

  @doc """
  Adds the docker container ID to the given vendors map. The container ID
  is retrieved from the given cgroup file, It's taken from the first cgroup
  in the file that meets the following requirements:

  - The definition must contain 3 parts separated by a colon.
  - It must specify the cpu subsystem.
  - The contianer ID is the last item in the cgroup path and it should
    be a 64-digit hex string.
  """
  def maybe_add_docker_container_id(vendors, cgroup_file) do
    case File.read(cgroup_file) do
      {:ok, content} ->
        cid = container_id_from_cgroup_file_content(content)

        if cid != nil do
          Map.put(vendors, :docker, %{id: cid})
        else
          vendors
        end

      _ ->
        vendors
    end
  end

  defp container_id_from_cgroup_file_content(content) do
    content
    |> String.split("\n", trim: true)
    |> Enum.find_value(&container_id_from_cgroup_definition/1)
  end

  defp container_id_from_cgroup_definition(cgroup) do
    with {:ok, cgroup_parts} <- validate_cgroup(cgroup),
         true <- is_cgroup_for_cpu_subsystem?(Enum.at(cgroup_parts, 1)),
         container_id <- container_id_from_cgroup_path(Enum.at(cgroup_parts, 2)),
         true <- Regex.match?(~r/[0-9a-f]{64,}/, container_id) do
      container_id
    else
      _ -> false
    end
  end

  defp container_id_from_cgroup_path(cgroup_path) do
    cgroup_path
    |> String.split("/")
    |> List.last()
  end

  defp is_cgroup_for_cpu_subsystem?(subsystems) do
    subsystems
    |> String.split(",")
    |> Enum.any?(fn x -> x == "cpu" end)
  end

  defp validate_cgroup(cgroup) do
    cgroup_parts = String.split(cgroup, ":")

    if length(cgroup_parts) == 3 do
      {:ok, cgroup_parts}
    else
      :error
    end
  end

  @aws_url "http://169.254.169.254/2016-09-02/dynamic/instance-identity/document"
  def maybe_add_aws(vendors, options \\ []) do
    Keyword.get(options, :aws_url, @aws_url)
    |> aws_vendor_hash()
    |> case do
      nil -> vendors
      aws_hash -> Map.put(vendors, :aws, aws_hash)
    end
  end

  def maybe_add_kubernetes(vendors) do
    System.get_env("KUBERNETES_SERVICE_HOST")
    |> case do
      nil -> vendors
      value -> Map.put(vendors, :kubernetes, %{kubernetes_service_host: value})
    end
  end

  @aws_vendor_data ["availabilityZone", "instanceId", "instanceType"]
  def aws_vendor_hash(url) do
    case :httpc.request(:get, {~c(#{url}), []}, [{:timeout, 100}], []) do
      {:ok, {{_, 200, 'OK'}, _headers, body}} ->
        case Jason.decode(body) do
          {:ok, data} -> Map.take(data, @aws_vendor_data)
          _ -> nil
        end

      _error ->
        nil
    end
  rescue
    exception ->
      NewRelic.log(:error, "Failed to fetch AWS metadata. #{inspect(exception)}")
      nil
  end
end
