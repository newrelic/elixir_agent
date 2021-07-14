defmodule NewRelic.Telemetry.Supervisor do
  use Supervisor

  @moduledoc false

  def start_link(_) do
    Supervisor.start_link(__MODULE__, [])
  end

  def init(_) do
    children = [
      NewRelic.Telemetry.Ecto.Supervisor,
      NewRelic.Telemetry.Redix,
      NewRelic.Telemetry.Plug,
      NewRelic.Telemetry.Phoenix,
      NewRelic.Telemetry.Absinthe
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
