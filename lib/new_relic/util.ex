defmodule NewRelic.Util do
  @moduledoc false

  alias NewRelic.Util.Vendor

  def hostname do
    Vendor.maybe_heroku_dyno_hostname() || get_hostname()
  end

  def pid, do: System.get_pid() |> String.to_integer()

  def time_to_ms({megasec, sec, microsec}),
    do: (megasec * 1_000_000 + sec) * 1_000 + round(microsec / 1_000)

  def process_name(pid) do
    case Process.info(pid, :registered_name) do
      nil -> nil
      {:registered_name, []} -> nil
      {:registered_name, name} -> name
    end
  end

  def metric_join(segments) when is_list(segments) do
    segments
    |> Enum.filter(& &1)
    |> Enum.map(&to_string/1)
    |> Enum.map(&String.replace_leading(&1, "/", ""))
    |> Enum.map(&String.replace_trailing(&1, "/", ""))
    |> Enum.join("/")
  end

  def deep_flatten(attrs) when is_list(attrs) do
    Enum.flat_map(attrs, &deep_flatten/1)
  end

  def deep_flatten({key, value}) when is_map(value) do
    Enum.flat_map(value, fn {k, v} -> deep_flatten({"#{key}.#{k}", v}) end)
  end

  def deep_flatten({key, value}) do
    [{key, value}]
  end

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
    |> Vendor.maybe_add_linux_boot_id()
    |> Vendor.maybe_add_cloud_vendors()
  end

  @mb 1024 * 1024
  defp get_system_memory() do
    case :memsup.get_system_memory_data()[:system_total_memory] do
      nil -> nil
      bytes -> trunc(bytes / @mb)
    end
  end

  defp get_hostname do
    with {:ok, name} <- :inet.gethostname(), do: to_string(name)
  end
end
