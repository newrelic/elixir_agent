defmodule QuantumExample.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      QuantumExample.Scheduler
    ]

    opts = [strategy: :one_for_one, name: QuantumExample.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
