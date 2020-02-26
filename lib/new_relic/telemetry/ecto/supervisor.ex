defmodule NewRelic.Telemetry.Ecto.Supervisor do
  @moduledoc false

  use DynamicSupervisor

  def start_link() do
    DynamicSupervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def start_child(otp_app) do
    DynamicSupervisor.start_child(__MODULE__, {NewRelic.Telemetry.Ecto, otp_app})
  end

  def init(:ok) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
