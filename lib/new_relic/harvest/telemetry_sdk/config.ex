defmodule NewRelic.Harvest.TelemetrySdk.Config do
  @moduledoc false

  @default %{
    logs_harvest_cycle: 5_000
  }
  def lookup(key) do
    Application.get_env(:new_relic_agent, key) || @default[key]
  end
end
