defmodule NewRelic.Util.Vendor do
  def maybe_add_linux_boot_id(util) do
    case File.read("/proc/sys/kernel/random/boot_id") do
      {:ok, boot_id} -> Map.put(util, "boot_id", boot_id)
      _ -> util
    end
  end

  def maybe_heroku_dyno_hostname do
    System.get_env("DYNO")
    |> case do
      nil -> nil
      "scheduler." <> _ -> "scheduler.*"
      "run." <> _ -> "run.*"
      name -> name
    end
  end

  @aws_url "http://169.254.169.254/2016-09-02/dynamic/instance-identity/document"
  def maybe_add_cloud_vendors(util, options \\ []) do
    Keyword.get(options, :aws_url, @aws_url)
    |> aws_vendor_hash()
    |> case do
      nil -> util
      aws_hash -> Map.put(util, :vendors, %{aws: aws_hash})
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
