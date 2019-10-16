defmodule NewRelic.Util.Vendor do
  @moduledoc false

  def maybe_add_vendors(util, options \\ []) do
    %{}
    |> maybe_add_aws(options)
    |> maybe_add_kubernetes()
    |> case do
      vendors when map_size(vendors) == 0 -> util
      vendors -> Map.put(util, :vendors, vendors)
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
