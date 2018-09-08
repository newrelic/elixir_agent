defmodule NewRelic.Util do
  @moduledoc false

  def hostname do
    with {:ok, name} <- :inet.gethostname(), do: to_string(name)
  end

  def pid, do: System.get_pid() |> String.to_integer()

  def post(url, body, headers) when is_binary(body),
    do: HTTPoison.post(url, body, headers)

  def post(url, body, headers),
    do: post(url, Jason.encode!(body), headers)

  def time_to_ms({megasec, sec, microsec}),
    do: (megasec * 1_000_000 + sec) * 1_000 + round(microsec / 1_000)

  def elixir_environment() do
    build_info = System.build_info()

    [
      ["Language", "Elixir"],
      ["Elixir Version", build_info[:version]],
      ["OTP Version", build_info[:otp_release]],
      ["Elixir build", build_info[:build]]
    ]
  end

  def utilization() do
    %{
      metadata_version: 3,
      logical_processors: :erlang.system_info(:logical_processors),
      total_ram_mib: get_system_memory(),
      hostname: hostname()
    }
    |> maybe_add_boot_id()
    |> maybe_add_vendors()
  end

  @mb 1024 * 1024
  defp get_system_memory() do
    case :memsup.get_system_memory_data()[:system_total_memory] do
      nil -> nil
      bytes -> trunc(bytes / @mb)
    end
  end

  defp maybe_add_boot_id(util) do
    case File.read("/proc/sys/kernel/random/boot_id") do
      {:ok, boot_id} -> Map.put(util, "boot_id", boot_id)
      _ -> util
    end
  end

  @aws_url "http://169.254.169.254/2016-09-02/dynamic/instance-identity/document"
  def maybe_add_vendors(util, options \\ []) do
    Keyword.get(options, :aws_url, @aws_url)
    |> aws_vendor_hash()
    |> case do
      nil -> util
      aws_hash -> Map.put(util, :vendors, %{aws: aws_hash})
    end
  end

  @aws_vendor_data ["availabilityZone", "instanceId", "instanceType"]
  defp aws_vendor_hash(url) do
    case HTTPoison.get(url, [], timeout: 100) do
      {:ok, %{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, data} -> Map.take(data, @aws_vendor_data)
          _ -> nil
        end

      _error ->
        nil
    end
  end
end
