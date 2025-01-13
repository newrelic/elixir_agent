defmodule NewRelic.OsMon do
  def start() do
    Application.ensure_all_started(:os_mon)
    :persistent_term.put(__MODULE__, true)
  end

  @mb 1024 * 1024
  def get_system_memory() do
    when_enabled(fn ->
      case :memsup.get_system_memory_data()[:system_total_memory] do
        nil -> nil
        bytes -> trunc(bytes / @mb)
      end
    end)
  end

  def util() do
    when_enabled(fn ->
      :cpu_sup.util()
    end)
  end

  defp when_enabled(fun, default \\ nil) do
    case :persistent_term.get(__MODULE__, false) do
      true -> fun.()
      false -> default
    end
  end
end
