defmodule NewRelic.Telemetry.Supervisor do
  use Supervisor

  @moduledoc false

  def start_link(_) do
    Supervisor.start_link(__MODULE__, [])
  end

  def init(_) do
    Supervisor.init(
      children(enabled: NewRelic.Config.enabled?()),
      strategy: :one_for_one
    )
  end

  defp children(enabled: true) do
    [
      NewRelic.Telemetry.Ecto.Supervisor,
      NewRelic.Telemetry.Redix,
      NewRelic.Telemetry.Plug,
      NewRelic.Telemetry.Phoenix,
      NewRelic.Telemetry.PhoenixLiveView,
      NewRelic.Telemetry.Oban,
      NewRelic.Telemetry.Finch,
      NewRelic.Telemetry.Absinthe
    ]
  end

  defp children(enabled: false) do
    []
  end
end
