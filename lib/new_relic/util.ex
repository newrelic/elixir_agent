defmodule NewRelic.Util do
  @moduledoc false

  def hostname do
    with {:ok, name} <- :inet.gethostname(), do: to_string(name)
  end

  def pid, do: System.get_pid() |> String.to_integer()

  def post(url, body, headers) when is_binary(body) do
    with url = to_charlist(url),
         headers = for({k, v} <- headers, do: {to_charlist(k), to_charlist(v)}) do
      :httpc.request(
        :post,
        {url, headers, 'application/json', body},
        [],
        []
      )
    end
  end

  def post(url, body, headers), do: post(url, Jason.encode!(body), headers)

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
      "metadata_version" => 3,
      "logical_processors" => :erlang.system_info(:logical_processors),
      "total_ram_mib" => nil,
      "hostname" => hostname()
    }
    |> maybe_add_boot_id()
  end

  defp maybe_add_boot_id(util) do
    case File.read("/proc/sys/kernel/random/boot_id") do
      {:ok, boot_id} -> Map.put(util, "boot_id", boot_id)
      _ -> util
    end
  end
end
