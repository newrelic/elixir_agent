defmodule NewRelic.Transaction.ErlangTraceSupervisor do
  use Supervisor

  @moduledoc false

  def start_link(_) do
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_) do
    enabled? = !Application.get_env(:new_relic_agent, :disable_erlang_trace, false)

    Supervisor.init(children(enabled: enabled?), strategy: :one_for_one)
  end

  def children(enabled: true), do: [NewRelic.Transaction.ErlangTrace]
  def children(enabled: false), do: []
end
