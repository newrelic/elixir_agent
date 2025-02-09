defmodule NewRelic.Util.Vendor do
  @moduledoc false

  def maybe_add_vendors(util, options \\ []) do
    %{}
    |> maybe_add_aws(options)
    |> maybe_add_kubernetes(options)
    |> maybe_add_docker(options)
    |> case do
      vendors when map_size(vendors) == 0 -> util
      vendors -> Map.put(util, :vendors, vendors)
    end
  end

  @aws_url "http://169.254.169.254/2016-09-02/dynamic/instance-identity/document"
  defp maybe_add_aws(vendors, options) do
    Keyword.get(options, :aws_url, @aws_url)
    |> aws_vendor_map()
    |> case do
      nil -> vendors
      aws_hash -> Map.put(vendors, :aws, aws_hash)
    end
  end

  defp maybe_add_kubernetes(vendors, _options) do
    System.get_env("KUBERNETES_SERVICE_HOST")
    |> case do
      nil -> vendors
      value -> Map.put(vendors, :kubernetes, %{kubernetes_service_host: value})
    end
  end

  @cgroup_filename "/proc/self/cgroup"
  defp maybe_add_docker(vendors, options) do
    Keyword.get(options, :cgroup_filename, @cgroup_filename)
    |> docker_vendor_map()
    |> case do
      nil -> vendors
      docker -> Map.put(vendors, :docker, docker)
    end
  end

  @cgroup_matcher ~r/\d+:.*cpu[,:].*(?<id>[0-9a-f]{64}).*/
  defp docker_vendor_map(cgroup_filename) do
    File.read(cgroup_filename)
    |> case do
      {:ok, cgroup_file} ->
        cgroup_file
        |> String.split("\n", trim: true)
        |> Enum.find_value(&Regex.named_captures(@cgroup_matcher, &1))

      _ ->
        nil
    end
  end

  @aws_vendor_data ["availabilityZone", "instanceId", "instanceType"]
  defp aws_vendor_map(url) do
    case :httpc.request(:get, {~c(#{url}), []}, [{:timeout, 100}], []) do
      {:ok, {{_, 200, ~c"OK"}, _headers, body}} ->
        case NewRelic.JSON.decode(to_string(body)) do
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
